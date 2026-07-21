#!/bin/bash
# Wan2.2 모델을 Network Volume 에 다운로드 (없을 때만 · 한 번만 · ~35GB)
# entrypoint.sh 가 첫 부팅 시 자동 호출 · 이후는 파일 존재 확인으로 스킵됨.
#
# 저장 위치는 반드시 볼륨 (/workspace/comfyui/models/) 이어야 다음 Pod 부팅부터 재사용됨.

set -e

VOLUME_PATH=${VOLUME_PATH:-/workspace/comfyui}
M="$VOLUME_PATH/models"
HF="https://huggingface.co"
W="$HF/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"

mkdir -p "$M/diffusion_models" "$M/loras" "$M/vae" "$M/text_encoders"

dl() {
    local url=$1 dest=$2 min_mb=${3:-10}
    if [ -f "$dest" ] && [ "$(du -m "$dest" | cut -f1)" -ge "$min_mb" ]; then
        echo "  ✅ 이미 있음: $(basename "$dest") ($(du -h "$dest" | cut -f1))"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    echo "  📥 $(basename "$dest") · min ${min_mb}MB"
    local auth=()
    [[ "$url" == *huggingface.co* ]] && [ -n "$HF_TOKEN" ] && auth=(-H "Authorization: Bearer $HF_TOKEN")
    curl -L --fail --retry 3 --retry-delay 5 "${auth[@]}" "$url" -o "$dest" \
        || { echo "  ❌ 실패: $dest"; rm -f "$dest"; return 1; }
}

echo "═══════════════════════════════════════════════════"
echo "📦 Wan2.2 다운로드 (~35GB · 볼륨: $M)"
echo "═══════════════════════════════════════════════════"

dl "$W/diffusion_models/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors" \
   "$M/diffusion_models/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors" 14000 &

dl "$W/diffusion_models/wan2.2_fun_camera_low_noise_14B_fp8_scaled.safetensors" \
   "$M/diffusion_models/wan2.2_fun_camera_low_noise_14B_fp8_scaled.safetensors" 14000 &

dl "$W/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" \
   "$M/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" 500 &

dl "$W/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" \
   "$M/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" 500 &

dl "$W/vae/wan_2.1_vae.safetensors" \
   "$M/vae/wan_2.1_vae.safetensors" 200 &

dl "$W/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
   "$M/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" 5000 &

wait

echo ""
echo "═══════════════════════════════════════════════════"
echo "✅ Wan2.2 다운로드 완료"
echo "  · high_noise: $(du -h "$M/diffusion_models/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors" 2>/dev/null | cut -f1)"
echo "  · low_noise : $(du -h "$M/diffusion_models/wan2.2_fun_camera_low_noise_14B_fp8_scaled.safetensors"  2>/dev/null | cut -f1)"
echo "  · umt5_xxl  : $(du -h "$M/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" 2>/dev/null | cut -f1)"
echo "  · wan_vae   : $(du -h "$M/vae/wan_2.1_vae.safetensors" 2>/dev/null | cut -f1)"
echo "═══════════════════════════════════════════════════"
