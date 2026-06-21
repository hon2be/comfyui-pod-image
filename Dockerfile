# ComfyUI + 커스텀 노드 + Claude Code + Comfy-Pilot MCP 미리 설치
# 모델은 CLAUDE.md 기반으로 Pod 첫 부팅 시 Claude Code가 자동 다운로드

FROM runpod/stable-diffusion:comfy-ui-6.0.0

LABEL maintainer="honeybee"
LABEL description="ComfyUI + IPAdapter + FaceID + Wan2.2 + Claude Code + Comfy-Pilot MCP"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ─────────────────────────────────────
# 환경변수 (RunPod 콘솔에서 override 가능)
# ─────────────────────────────────────
ENV COMFY_PATH=/ComfyUI
ENV VOLUME_PATH=/workspace/comfyui

# 🔑 포트 옵션 (실행 시 변경 가능)
ENV COMFYUI_PORT=3000
ENV COMFYUI_HOST=0.0.0.0

# 작업 경로 (옵션)
ENV WORKFLOWS_PATH=/workspace/comfyui/user/default/workflows
ENV WORKING_DIR=/workspace/work

# 모델 자동 다운로드 (Claude가 CLAUDE.md 보고 처리)
ENV AUTO_DOWNLOAD_MODELS=true

# ─────────────────────────────────────
# 시스템 패키지
# ─────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl wget git tmux htop nano vim ca-certificates jq \
        ffmpeg libgl1 libglib2.0-0 build-essential \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────
# Node.js 20 + Claude Code
# ─────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────
# 커스텀 노드 (이미 있으면 skip, 실패해도 빌드 계속)
# ─────────────────────────────────────
WORKDIR ${COMFY_PATH}/custom_nodes

RUN for repo in \
        "https://github.com/ltdrdata/ComfyUI-Manager.git" \
        "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git" \
        "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
        "https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git" \
        "https://github.com/Fannovel16/comfyui_controlnet_aux.git" \
        "https://github.com/cubiq/ComfyUI_essentials.git" \
        "https://github.com/rgthree/rgthree-comfy.git" \
        "https://github.com/chflame163/ComfyUI_LayerStyle.git" \
        "https://github.com/kijai/ComfyUI-IC-Light.git" \
        "https://github.com/huchenlei/ComfyUI-openpose-editor.git" \
        "https://github.com/GeekyGhost/ComfyUI-GeekyRemB.git" \
        "https://github.com/biegert/ComfyUI-CLIPSeg.git" \
        "https://github.com/ConstantineB6/Comfy-Pilot.git"; do \
        name=$(basename "$repo" .git); \
        if [ -d "$name" ]; then \
            echo "✅ 이미 있음: $name"; \
        else \
            echo "📥 git clone $name"; \
            git clone --depth 1 "$repo" || echo "⚠️ $name clone 실패 (계속 진행)"; \
        fi; \
    done

# ─────────────────────────────────────
# PyTorch 2.7.0 + CUDA 12.8 (Blackwell SM 12.0 지원)
# NVIDIA RTX PRO 4500 등 Blackwell 아키텍처 GPU 필수
# 기본 이미지의 PyTorch(2.6.x/cu124)는 SM 9.0까지만 지원 → SM 12.0에서 CUDA kernel 오류 발생
# ─────────────────────────────────────
RUN pip install --no-cache-dir \
        torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
        --index-url https://download.pytorch.org/whl/cu128

# ─────────────────────────────────────
# 핵심 Python 패키지 — Impact-Pack/IPAdapter/CLIPSeg 필수 의존성
# ─────────────────────────────────────
RUN pip install --no-cache-dir \
        segment_anything piexif ultralytics dill \
        insightface onnxruntime \
        transformers \
        opencv-python-headless scipy scikit-image einops \
        fastapi uvicorn websockets \
        "huggingface_hub[hf_transfer]"

# ─────────────────────────────────────
# 각 커스텀 노드의 requirements.txt 설치 (있는 경우만)
# ─────────────────────────────────────
RUN for node in ComfyUI-Impact-Pack ComfyUI-Impact-Subpack ComfyUI_IPAdapter_plus \
                ComfyUI-GeekyRemB ComfyUI_LayerStyle ComfyUI-IC-Light \
                rgthree-comfy comfyui_controlnet_aux ComfyUI-CLIPSeg \
                ComfyUI_essentials; do \
        req="${COMFY_PATH}/custom_nodes/${node}/requirements.txt"; \
        if [ -f "$req" ]; then \
            echo "📦 [$node] requirements.txt 설치"; \
            pip install --no-cache-dir -r "$req" || echo "⚠️ $node 의존성 일부 실패 (계속)"; \
        else \
            echo "ℹ️ [$node] requirements.txt 없음 (skip)"; \
        fi; \
    done; \
    if [ -d "${COMFY_PATH}/custom_nodes/Comfy-Pilot" ]; then \
        echo "📦 Comfy-Pilot editable install"; \
        pip install --no-cache-dir -e "${COMFY_PATH}/custom_nodes/Comfy-Pilot" \
            || echo "⚠️ Comfy-Pilot pyproject 설치 실패 (수동 의존성으로 대체)"; \
    fi

# ─────────────────────────────────────
# ComfyUI v0.3.x 호환성 패치
# Impact-Pack: comfy.samplers.SCHEDULER_HANDLERS → SCHEDULER_NAMES (v0.3.x에서 이름 변경)
# ─────────────────────────────────────
RUN find ${COMFY_PATH}/custom_nodes/ComfyUI-Impact-Pack \
         ${COMFY_PATH}/custom_nodes/ComfyUI-Impact-Subpack \
         -name "*.py" 2>/dev/null \
    | xargs sed -i 's/comfy\.samplers\.SCHEDULER_HANDLERS/comfy.samplers.SCHEDULER_NAMES/g' \
    || true

# ─────────────────────────────────────
# Impact-Pack/Subpack 정상 로드 검증
# ─────────────────────────────────────
RUN python -c "import segment_anything, ultralytics, insightface, transformers; print('✅ 핵심 패키지 import OK')" \
    || (echo "❌ 핵심 패키지 import 실패" && exit 1)

# ─────────────────────────────────────
# 사용자 워크플로우 JSON (이미지에 동봉)
# ─────────────────────────────────────
COPY configs/workflows /opt/workflows-template

# ─────────────────────────────────────
# Claude Code 설정 + CLAUDE.md (모델 자동 다운로드 명세)
# ─────────────────────────────────────
COPY configs/claude /opt/claude-template

# ─────────────────────────────────────
# Entrypoint + Helper 스크립트
# ─────────────────────────────────────
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 3000 8188 8888 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
