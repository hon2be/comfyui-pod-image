#!/bin/bash
# 볼륨에 ComfyUI 본체가 없을 때만 실행 · 한 번만 · 이후 부팅에서 스킵됨

set -e

VOLUME_PATH=${VOLUME_PATH:-/workspace/comfyui}
COMFY_PATH=${COMFY_PATH:-$VOLUME_PATH/ComfyUI}

echo "═══════════════════════════════════════════════════"
echo "📦 ComfyUI Bootstrap · 최초 1회 (~5분)"
echo "═══════════════════════════════════════════════════"

# 1. ComfyUI 본체 clone
echo "[1/4] ComfyUI clone"
git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git $COMFY_PATH

cd $COMFY_PATH
echo "[2/4] ComfyUI requirements install"
pip install --no-cache-dir -r requirements.txt

# 2. 커스텀 노드 clone (볼륨에 없는 것만)
echo "[3/4] 커스텀 노드 clone"
mkdir -p $VOLUME_PATH/custom_nodes
cd $VOLUME_PATH/custom_nodes

for repo in \
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
    "https://github.com/time-river/ComfyUI-CLIPSeg.git" \
    "https://github.com/ConstantineB6/Comfy-Pilot.git" \
    "https://github.com/XLabs-AI/x-flux-comfyui.git"; do
    name=$(basename "$repo" .git)
    if [ -d "$name" ]; then
        echo "  ✅ 이미 있음: $name"
    else
        echo "  📥 $name"
        git clone --depth 1 "$repo" || echo "  ⚠️ $name 실패 (계속)"
    fi
done

# 3. 커스텀 노드 requirements install (있는 것만)
echo "[4/4] 커스텀 노드 pip install"
for node in ComfyUI-Impact-Pack ComfyUI-Impact-Subpack ComfyUI_IPAdapter_plus \
            ComfyUI-GeekyRemB ComfyUI_LayerStyle ComfyUI-IC-Light \
            rgthree-comfy comfyui_controlnet_aux ComfyUI-CLIPSeg \
            ComfyUI_essentials x-flux-comfyui; do
    req="$VOLUME_PATH/custom_nodes/${node}/requirements.txt"
    if [ -f "$req" ]; then
        pip install --no-cache-dir -r "$req" || echo "  ⚠️ $node 의존성 일부 실패"
    fi
done

if [ -d "$VOLUME_PATH/custom_nodes/Comfy-Pilot" ]; then
    pip install --no-cache-dir -e "$VOLUME_PATH/custom_nodes/Comfy-Pilot" || \
        echo "  ⚠️ Comfy-Pilot 설치 실패"
fi

# CLIPSeg __init__.py 생성 · 노드 로드용
printf '%s\n' \
    'import sys, os' \
    'sys.path.insert(0, os.path.join(os.path.dirname(__file__), "custom_nodes"))' \
    'from clipseg import NODE_CLASS_MAPPINGS' \
    'NODE_DISPLAY_NAME_MAPPINGS = {}' \
    '__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS"]' \
    > $VOLUME_PATH/custom_nodes/ComfyUI-CLIPSeg/__init__.py 2>/dev/null || true

# ComfyUI 심링크 · custom_nodes/models/input/output/user 를 볼륨으로
for dir in custom_nodes models input output user; do
    if [ -d "$COMFY_PATH/$dir" ] && [ ! -L "$COMFY_PATH/$dir" ]; then
        rm -rf "$COMFY_PATH/$dir"
    fi
    ln -sfn "$VOLUME_PATH/$dir" "$COMFY_PATH/$dir"
done

echo "═══════════════════════════════════════════════════"
echo "✅ Bootstrap 완료 · 다음 부팅부터는 이 단계 스킵됨"
echo "═══════════════════════════════════════════════════"
