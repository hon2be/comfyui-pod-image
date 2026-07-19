# 슬림 이미지 · ComfyUI 본체는 볼륨에 상주 · 이미지는 base + 얇은 config layer 만
#
# 기존 fat 이미지 문제:
#   - 20GB · 매 Pod 부팅 시 host에 없으면 pull 10~20분
#   - Community Cloud는 host 캐시 히트 확률 낮음
#
# 슬림 이미지 원리:
#   - Base = runpod/pytorch (~5GB · RunPod 공식이라 대부분 host에 이미 캐시됨)
#   - 우리 layer = 500MB 정도 (system deps + custom node pip deps + configs + entrypoint)
#   - ComfyUI 코드 + 커스텀 노드 소스 + 모델 = 전부 볼륨 (`esjmoaksvu`)
#   - 부팅 시간: 20분 → 2~3분

FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

LABEL maintainer="honeybee"
LABEL description="Slim base · ComfyUI runtime resides on network volume"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# 런타임 환경변수 (RunPod 콘솔에서 override 가능)
ENV VOLUME_PATH=/workspace/comfyui
ENV COMFY_PATH=/workspace/comfyui/ComfyUI
ENV COMFYUI_PORT=3000
ENV COMFYUI_HOST=0.0.0.0
ENV WORKFLOWS_PATH=/workspace/comfyui/user/default/workflows
ENV WORKING_DIR=/workspace/work
ENV AUTO_DOWNLOAD_MODELS=true

# ─────────────────────────────────────
# 시스템 패키지 (얇게)
# ─────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl wget git tmux htop nano vim ca-certificates jq \
        ffmpeg libgl1 libglib2.0-0 build-essential \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────
# Node.js + Claude Code
# ─────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

# ─────────────────────────────────────
# 커스텀 노드가 요구하는 Python deps · 볼륨 재사용성 위해 이미지에 bake
# (매 부팅 시 pip install 하면 느림)
# ─────────────────────────────────────
RUN pip install --no-cache-dir \
        segment_anything piexif ultralytics dill \
        insightface onnxruntime \
        transformers \
        opencv-python-headless scipy scikit-image einops \
        fastapi uvicorn websockets \
        "huggingface_hub[hf_transfer]" \
        sqlalchemy alembic aiohttp av pyyaml \
        spandrel kornia soundfile blake3 \
        comfy-aimdo

# torch 강제 재설치 · CUDA 버전 확보 (다른 pip 이 CPU 버전으로 덮어쓰는 것 방지)
# base image (runpod/pytorch:2.4.0-cuda12.4.1) 가 지정한 torch 를 유지하려면 이 단계 필수.
RUN pip install --no-cache-dir --force-reinstall \
        torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1 \
        --index-url https://download.pytorch.org/whl/cu124

# 패키지 버전 핀 (custom node requirements가 downgrade 방지)
RUN pip install --no-cache-dir \
        "numpy>=1.26.4" \
        "pillow>=10.1.0" \
        "transformers>=4.45.0" \
        "protobuf>=4.25.1"

# ─────────────────────────────────────
# 사용자 워크플로우 JSON + CLAUDE.md (이미지에 동봉)
# 볼륨 부트스트랩 스크립트도 함께
# ─────────────────────────────────────
COPY configs/workflows /opt/workflows-template
COPY configs/claude /opt/claude-template
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/bootstrap-comfyui.sh /usr/local/bin/bootstrap-comfyui.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/bootstrap-comfyui.sh

WORKDIR /workspace
EXPOSE 3000 8188 8888 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
