#!/bin/bash
# Pod 시작 시 자동 실행 — DNS 수정 + Symlink + ComfyUI 시작 + MCP 설정 + Claude 설정 복사
# 모델 다운로드는 사용자가 Claude Code 실행 후 CLAUDE.md 보고 자동 처리

set -e

COMFY_PATH=${COMFY_PATH:-/ComfyUI}
VOLUME_PATH=${VOLUME_PATH:-/workspace/comfyui}
COMFYUI_PORT=${COMFYUI_PORT:-3000}
COMFYUI_HOST=${COMFYUI_HOST:-0.0.0.0}
WORKING_DIR=${WORKING_DIR:-/workspace/work}

# ─────────────────────────────────────
# 0. DNS 자동 수정 (Docker 내부 DNS 문제 우회)
# ─────────────────────────────────────
echo "🔧 DNS 설정 (Public DNS 강제)"
cat > /etc/resolv.conf <<DNS_EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 9.9.9.9
DNS_EOF

# resolv.conf immutable 시도 (Docker 덮어쓰기 방지)
chattr +i /etc/resolv.conf 2>/dev/null || true

# 인터넷 확인
if ! curl -sf --connect-timeout 5 https://google.com >/dev/null 2>&1; then
  echo "⚠️ 인터넷 연결 실패 — 5초 후 재시도"
  sleep 5
  chattr -i /etc/resolv.conf 2>/dev/null || true
  cat > /etc/resolv.conf <<DNS_EOF
nameserver 8.8.4.4
nameserver 1.0.0.1
DNS_EOF
fi

echo "═══════════════════════════════════════════════════"
echo "🚀 ComfyUI Pod 부팅"
echo "  Port: $COMFYUI_PORT (변경: -e COMFYUI_PORT=...)"
echo "  ComfyUI: $COMFY_PATH"
echo "  Volume:  $VOLUME_PATH"
echo "═══════════════════════════════════════════════════"

# ─────────────────────────────────────
# 1. Network Volume 폴더 구조 확보 (첫 실행만)
# ─────────────────────────────────────
echo "📁 Network Volume 구조 확보"
mkdir -p $VOLUME_PATH/models/{checkpoints,loras,vae,text_encoders,diffusion_models,controlnet,ipadapter,clip_vision,ultralytics/bbox,insightface}
mkdir -p $VOLUME_PATH/{input,output,user/default/workflows}
mkdir -p $WORKING_DIR

# ─────────────────────────────────────
# 2. /ComfyUI ↔ Network Volume Symlink
# ─────────────────────────────────────
echo "🔗 Symlink 연결"
for dir in models input output user; do
  if [ -d "$COMFY_PATH/$dir" ] && [ ! -L "$COMFY_PATH/$dir" ]; then
    mv "$COMFY_PATH/$dir" "$COMFY_PATH/${dir}_default" 2>/dev/null || true
  fi
  ln -sfn "$VOLUME_PATH/$dir" "$COMFY_PATH/$dir"
done

# ─────────────────────────────────────
# 3. ComfyUI 백그라운드 시작 (포트 환경변수 사용)
# ─────────────────────────────────────
echo "🎨 ComfyUI 시작 (port $COMFYUI_PORT)"
cd $COMFY_PATH
nohup python main.py --listen $COMFYUI_HOST --port $COMFYUI_PORT --disable-auto-launch \
  > /workspace/comfy.log 2>&1 &

# 응답 대기
echo "  ⏳ ComfyUI 응답 대기..."
for i in {1..60}; do
  if curl -sf http://127.0.0.1:$COMFYUI_PORT/system_stats > /dev/null 2>&1; then
    echo "  ✅ ComfyUI 준비 완료"
    break
  fi
  sleep 2
done

# ─────────────────────────────────────
# 4. Comfy-Pilot .comfyui_url 명시 (포트 폴백 버그 우회)
# ─────────────────────────────────────
echo "http://127.0.0.1:$COMFYUI_PORT" > $COMFY_PATH/custom_nodes/Comfy-Pilot/.comfyui_url 2>/dev/null || true

# ─────────────────────────────────────
# 4.5 사용자 워크플로우 JSON 복사 (없는 것만)
# ─────────────────────────────────────
echo "📄 워크플로우 복사 (없는 것만)"
mkdir -p $VOLUME_PATH/user/default/workflows
cp -n /opt/workflows-template/*.json $VOLUME_PATH/user/default/workflows/ 2>/dev/null || true
echo "  현재 워크플로우: $(ls $VOLUME_PATH/user/default/workflows/*.json 2>/dev/null | wc -l)개"

# ─────────────────────────────────────
# 5. Claude Code 설정 셋업 (~/.claude)
# ─────────────────────────────────────
echo "🤖 Claude Code 설정"
mkdir -p ~/.claude/commands

# CLAUDE.md (모델 다운로드 명세 — 첫 실행 시 Claude가 자동 처리)
if [ ! -f ~/.claude/CLAUDE.md ]; then
  envsubst < /opt/claude-template/CLAUDE.md > ~/.claude/CLAUDE.md
fi

# MCP user scope 등록 (다른 세션에서도 보임)
cat > ~/.claude/.mcp.json <<EOF
{
  "mcpServers": {
    "comfyui": {
      "command": "node",
      "args": ["$COMFY_PATH/custom_nodes/Comfy-Pilot/mcp_server.js"],
      "env": { "COMFYUI_URL": "http://127.0.0.1:$COMFYUI_PORT" }
    }
  }
}
EOF

# settings.json (Pod 환경 기본값)
if [ ! -f ~/.claude/settings.json ]; then
  cp /opt/claude-template/settings.json ~/.claude/settings.json 2>/dev/null || true
fi

# slash commands 복사
cp -n /opt/claude-template/commands/*.md ~/.claude/commands/ 2>/dev/null || true

# Network Volume에 영구 저장 (Pod 재생성 시 유지)
if [ ! -L "$VOLUME_PATH/.claude" ]; then
  mkdir -p $VOLUME_PATH/.claude
  cp -rn ~/.claude/* $VOLUME_PATH/.claude/ 2>/dev/null || true
fi

# ─────────────────────────────────────
# 6. 안내 출력
# ─────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "✅ Pod 준비 완료"
echo "═══════════════════════════════════════════════════"
echo "🌐 ComfyUI:    https://[POD-ID]-${COMFYUI_PORT}.proxy.runpod.net"
echo "📁 작업 폴더:  $WORKING_DIR"
echo "📦 모델 위치:  $VOLUME_PATH/models/ (영구)"
echo ""
echo "🤖 Claude Code 시작:"
echo "   cd $WORKING_DIR && claude"
echo ""
echo "   첫 실행 시 ~/.claude/CLAUDE.md 자동 읽음"
echo "   → 모델 자동 다운로드 시작 (네트워크 빠름, ~20분)"
echo ""
echo "═══════════════════════════════════════════════════"

# ─────────────────────────────────────
# 7. 컨테이너 유지 (인자 있으면 실행, 없으면 로그 tail)
# ─────────────────────────────────────
if [ $# -gt 0 ]; then
  exec "$@"
else
  tail -f /workspace/comfy.log
fi
