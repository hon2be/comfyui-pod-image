#!/bin/bash
# Pod 부팅 시 자동 실행 · 슬림 이미지용
# 볼륨에 ComfyUI 없으면 bootstrap · 있으면 즉시 실행

set -e

VOLUME_PATH=${VOLUME_PATH:-/workspace/comfyui}
COMFY_PATH=${COMFY_PATH:-$VOLUME_PATH/ComfyUI}
COMFYUI_PORT=${COMFYUI_PORT:-3000}
COMFYUI_HOST=${COMFYUI_HOST:-0.0.0.0}
WORKING_DIR=${WORKING_DIR:-/workspace/work}

echo "═══════════════════════════════════════════════════"
echo "🚀 ComfyUI Slim Pod 부팅"
echo "  Volume: $VOLUME_PATH"
echo "  ComfyUI: $COMFY_PATH"
echo "  Port: $COMFYUI_PORT"
echo "═══════════════════════════════════════════════════"

# ─────────────────────────────────────
# 1. DNS 자동 수정
# ─────────────────────────────────────
echo "🔧 DNS 설정"
cat > /etc/resolv.conf <<DNS_EOF || true
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 9.9.9.9
DNS_EOF
chattr +i /etc/resolv.conf 2>/dev/null || true

# ─────────────────────────────────────
# 1.5. SSH 서버 · PUBLIC_KEY env 로 인증 · 22 포트 노출된 파드에서만 접속 가능
# ─────────────────────────────────────
if [ -n "$PUBLIC_KEY" ]; then
    echo "🔑 SSH 셋업 (PUBLIC_KEY 감지)"
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "$PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    # sshd host keys · 없으면 생성
    ssh-keygen -A 2>/dev/null || true
    # PasswordAuthentication 끄고 · root 로그인 허용
    sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    /usr/sbin/sshd -D -p 22 &
    echo "  ✅ sshd 시작 (port 22 · key auth)"
else
    echo "🔑 PUBLIC_KEY 없음 · sshd 건너뜀"
fi

# ─────────────────────────────────────
# 2. 볼륨 폴더 확보
# ─────────────────────────────────────
mkdir -p $VOLUME_PATH/{models/{checkpoints,loras,vae,text_encoders,diffusion_models,controlnet,ipadapter,clip_vision,ultralytics/bbox,insightface,depthanything},custom_nodes,input,output,user/default/workflows}
mkdir -p $WORKING_DIR

# ─────────────────────────────────────
# 3. ComfyUI 부트스트랩 (없을 때만 · 한 번)
#    있으면 · 매 부팅 시 git pull 로 최신 유지 (파이썬 deps 이미지 층과 동기화)
# ─────────────────────────────────────
if [ ! -f "$COMFY_PATH/main.py" ]; then
    echo "⚠️  ComfyUI 볼륨에 없음 · bootstrap 실행"
    /usr/local/bin/bootstrap-comfyui.sh
else
    if [ -d "$COMFY_PATH/.git" ]; then
        echo "🔄 ComfyUI git pull (볼륨 최신화)"
        cd $COMFY_PATH && git pull --rebase --autostash 2>&1 | tail -5 || \
            echo "⚠️  git pull 실패 · 그대로 진행"
    else
        echo "⚠️  ComfyUI 가 git repo 아님 · 강제 재클론"
        rm -rf "$COMFY_PATH.old" && mv "$COMFY_PATH" "$COMFY_PATH.old" 2>/dev/null || true
        /usr/local/bin/bootstrap-comfyui.sh
    fi
fi

# ─────────────────────────────────────
# 3.5. WAN2.2 · AUTO_DOWNLOAD_WAN22=true 이면 볼륨에 없을 때만 다운로드
# ─────────────────────────────────────
WAN_HIGH="$VOLUME_PATH/models/diffusion_models/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors"
if [ "${AUTO_DOWNLOAD_WAN22:-false}" = "true" ] && [ ! -f "$WAN_HIGH" ]; then
    echo "🎬 WAN2.2 볼륨에 없음 · 자동 다운로드 시작 (~35GB · 5-10분)"
    /usr/local/bin/download-wan22.sh || echo "⚠️ WAN2.2 다운로드 실패 · 이후 수동 재시도 가능"
elif [ -f "$WAN_HIGH" ]; then
    echo "🎬 WAN2.2 이미 볼륨에 있음 · 스킵"
fi

# ─────────────────────────────────────
# 4. 워크플로우 JSON · 이미지에 동봉된 것 복사 (없는 것만)
# ─────────────────────────────────────
if [ -d /opt/workflows-template ]; then
    cp -n /opt/workflows-template/*.json $VOLUME_PATH/user/default/workflows/ 2>/dev/null || true
    echo "📄 워크플로우: $(ls $VOLUME_PATH/user/default/workflows/*.json 2>/dev/null | wc -l)개"
fi

# ─────────────────────────────────────
# 5. Claude Code 설정 셋업 (~/.claude)
# ─────────────────────────────────────
mkdir -p ~/.claude/commands
if [ ! -f ~/.claude/CLAUDE.md ] && [ -f /opt/claude-template/CLAUDE.md ]; then
    envsubst < /opt/claude-template/CLAUDE.md > ~/.claude/CLAUDE.md
fi
if [ ! -f ~/.claude/settings.json ] && [ -f /opt/claude-template/settings.json ]; then
    cp /opt/claude-template/settings.json ~/.claude/settings.json
fi
[ -d /opt/claude-template/commands ] && cp -n /opt/claude-template/commands/*.md ~/.claude/commands/ 2>/dev/null || true

# Comfy-Pilot MCP 등록 (custom_nodes/Comfy-Pilot 가 볼륨에 있으면)
if [ -f "$VOLUME_PATH/custom_nodes/Comfy-Pilot/mcp_server.py" ]; then
    cat > ~/.claude/.mcp.json <<EOF
{
  "mcpServers": {
    "comfyui": {
      "command": "python",
      "args": ["$VOLUME_PATH/custom_nodes/Comfy-Pilot/mcp_server.py"],
      "env": { "COMFYUI_URL": "http://127.0.0.1:$COMFYUI_PORT" }
    }
  }
}
EOF
fi

# ─────────────────────────────────────
# 6. Comfy-Pilot .comfyui_url 명시
# ─────────────────────────────────────
[ -d "$VOLUME_PATH/custom_nodes/Comfy-Pilot" ] && \
    echo "http://127.0.0.1:$COMFYUI_PORT" > $VOLUME_PATH/custom_nodes/Comfy-Pilot/.comfyui_url 2>/dev/null || true

# ─────────────────────────────────────
# 7. ComfyUI 백그라운드 시작
# ─────────────────────────────────────
echo "🎨 ComfyUI 시작 (port $COMFYUI_PORT)"
cd $COMFY_PATH
nohup python main.py --listen $COMFYUI_HOST --port $COMFYUI_PORT --disable-auto-launch \
    > /workspace/comfy.log 2>&1 &

# 응답 대기
echo "  ⏳ ComfyUI 응답 대기..."
for i in {1..60}; do
    if curl -sf http://127.0.0.1:$COMFYUI_PORT/system_stats > /dev/null 2>&1; then
        echo "  ✅ ComfyUI 준비 완료 ($((i*2))s)"
        break
    fi
    sleep 2
done

# ─────────────────────────────────────
# 8. 안내
# ─────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "✅ Slim Pod 준비 완료"
echo "═══════════════════════════════════════════════════"
echo "🌐 ComfyUI:    https://[POD-ID]-${COMFYUI_PORT}.proxy.runpod.net"
echo "📁 작업 폴더:  $WORKING_DIR"
echo "📦 모델 위치:  $VOLUME_PATH/models/"
echo ""
echo "🤖 Claude Code:"
echo "   cd $WORKING_DIR && claude"
echo "═══════════════════════════════════════════════════"

# ─────────────────────────────────────
# 9. 컨테이너 유지 · 인자 있으면 실행 · 없으면 log tail
# ─────────────────────────────────────
if [ $# -gt 0 ]; then
    exec "$@"
else
    tail -f /workspace/comfy.log
fi
