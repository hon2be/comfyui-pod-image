# 🎯 honeybee의 ComfyUI Pod 환경

> **이 파일은 Pod의 Claude Code가 실행될 때 자동으로 읽힘.**
> 첫 실행 시 아래 "🚀 자동 실행 흐름"을 그대로 진행할 것.

---

## 👤 사용자

- **이름**: honeybee
- **언어**: 한국어 (해요체)
- **비용 한도**: RunPod GPU 시간당 5,000원
- **ComfyUI 포트**: `${COMFYUI_PORT}` (환경변수, 기본 3000)

## 🔑 환경변수

| 변수 | 용도 | 필수 여부 |
|------|------|----------|
| `HF_TOKEN` | HuggingFace 빠른 다운로드 | 선택 |
| `CIVITAI_TOKEN` | Juggernaut XL, 한복 LoRA | **한복 작업 시 필수** |

미설정 시 사용자에게 안내하고 진행.

---

## 🚀 자동 실행 흐름 (Claude Code 첫 실행 시 무조건 수행)

### Step 1. 인사 + 환경 진단

```
👋 honeybee의 ComfyUI Pod 환경입니다.

📊 진단 결과:
  ✅ ComfyUI 실행 중 (port 3000)
  ✅ 워크플로우: N개 동봉
  ⚠️ 모델: 0/M (다운로드 필요)
  💾 Network Volume 여유: XGB

작업할 워크플로우를 골라주세요:
```

진단 명령:
```bash
ls /workspace/comfyui/user/default/workflows/*.json 2>/dev/null | wc -l
ls /workspace/comfyui/models/checkpoints/ 2>/dev/null
df -h /workspace
curl -sf http://127.0.0.1:${COMFYUI_PORT}/system_stats >/dev/null && echo OK || echo X
```

### Step 2. 동봉된 워크플로우 리스트 표시

```
📂 사용 가능한 워크플로우 (18개)

🇰🇷 한복/한국 전통
   1) Han.json              — 한복 캐릭터 (Juggernaut + 한복 LoRA + FaceID)
   2) hanbok_pose.json      — 한복 포즈 (Juggernaut + 한복 LoRA + OpenPose)
   3) hanbok_sitting_pose.json — 한복 앉은 포즈

🎬 비디오
   4) wan2.2_fun_camera.json — Wan2.2 Fun Camera 5초 영상

👧 캐릭터/일러스트
   5) Cute Girl.json        — 큐트한 캐릭터 (realisticAsian + IPAdapter)
   6) MyGirl.json           — 본인 캐릭터 (faceid SD1.5)
   7) clothing.json         — 의상 작업 (IPAdapter PLUS)

🎮 3D
   8) 3d_workflow.json
   9) text2_3d_isometric.json
  10) sv3d_cat_pipeline.json

🟨 픽셀아트
  11) Game Item.json

🛠 기타
  12) seethrough.json
  13) set layer.json
  14-18) (백업/임시 파일)

작업할 번호를 알려주세요 (여러 개도 가능, 예: 1,4):
```

### Step 3. 사용자 선택 → 필요 항목 매핑

아래 표 참고:

| 워크플로우 | 필요 모델 (체크포인트 + LoRA + 기타) |
|-----------|------|
| **1) Han.json** | Juggernaut XL + hangbokXL_dangui + OpenPoseXL2 + FaceID v2 + clip-vision-vit-h + face_yolov8m + hand_yolov8s |
| **2) hanbok_pose.json** | Juggernaut XL + hangbokXL_dangui + OpenPoseXL2 |
| **3) hanbok_sitting_pose.json** | 2번과 동일 |
| **4) wan2.2_fun_camera.json** | Wan2.2 high/low 14B + Lightning LoRA × 2 + umt5_xxl + wan_2.1_vae |
| **5) Cute Girl.json** | beautifulRealistic_asian_v7 + ip-adapter-plus_sdxl + clip-vision-vit-h |
| **6) MyGirl.json** | beautifulRealistic_asian_v7 + faceid.plus.sd15 + faceid.sd15 |
| **7) clothing.json** | beautifulRealistic_asian_v7 + ip-adapter-plus_sdxl |
| **8-10) 3D** | TripoSR/SV3D 모델 (옵션) |
| **11) Game Item.json** | pixelArtDiffusionXL_spriteShaper |
| **12) seethrough.json** | SeeThrough 모델 (별도, 큼) |

### Step 4. 다운로드 실행

선택한 워크플로우의 모델을 **누락된 것만** 다운로드.

```bash
# 헬퍼 함수
M=/workspace/comfyui/models
HF="https://huggingface.co"

dl() {
  local url=$1 dest=$2 min_mb=${3:-10}
  if [ -f "$dest" ] && [ $(du -m "$dest" | cut -f1) -ge "$min_mb" ]; then
    echo "  ✅ 이미 있음: $(basename $dest)"
    return
  fi
  mkdir -p $(dirname "$dest")
  echo "  📥 $(basename $dest)"
  local auth=()
  [[ "$url" == *huggingface.co* ]] && [ -n "$HF_TOKEN" ] && auth=(-H "Authorization: Bearer $HF_TOKEN")
  [[ "$url" == *civitai.com* ]] && auth=(-H "Authorization: Bearer $CIVITAI_TOKEN")
  curl -L --fail --retry 3 "${auth[@]}" "$url" -o "$dest" || { rm -f "$dest"; return 1; }
}
```

#### 워크플로우별 다운로드 함수

**한복 (1, 2, 3 공통)**:
```bash
download_hanbok() {
  if [ -z "$CIVITAI_TOKEN" ]; then
    echo "❌ CIVITAI_TOKEN 필수. https://civitai.com/user/account 에서 발급 후:"
    echo "   export CIVITAI_TOKEN=..."
    return 1
  fi
  dl "https://civitai.com/api/download/models/1759168" "$M/checkpoints/juggernautXL_ragnarok.safetensors" 6000 &
  dl "https://civitai.com/api/download/models/263359"  "$M/loras/hangbokXL_dangui.safetensors" 70 &
  dl "$HF/thibaud/controlnet-openpose-sdxl-1.0/resolve/main/OpenPoseXL2.safetensors" "$M/controlnet/OpenPoseXL2.safetensors" 4000 &
  # Han.json 전용 추가
  dl "$HF/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "$M/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin" 1300 &
  dl "$HF/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" "$M/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" 300 &
  dl "$HF/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$M/clip_vision/ViT-H-14-laion2B-s32B-b79K.safetensors" 2000 &
  dl "$HF/Bingsu/adetailer/resolve/main/face_yolov8m.pt" "$M/ultralytics/bbox/face_yolov8m.pt" 30 &
  dl "$HF/Bingsu/adetailer/resolve/main/hand_yolov8s.pt" "$M/ultralytics/bbox/hand_yolov8s.pt" 15 &
  wait
}
```

**Wan2.2 비디오 (4)**:
```bash
download_wan22() {
  W="$HF/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"
  dl "$W/diffusion_models/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors" "$M/diffusion_models/wan2.2_fun_camera_high_noise_14B_fp8_scaled.safetensors" 14000 &
  dl "$W/diffusion_models/wan2.2_fun_camera_low_noise_14B_fp8_scaled.safetensors"  "$M/diffusion_models/wan2.2_fun_camera_low_noise_14B_fp8_scaled.safetensors" 14000 &
  dl "$W/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" "$M/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" 500 &
  dl "$W/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"  "$M/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" 500 &
  dl "$W/vae/wan_2.1_vae.safetensors" "$M/vae/wan_2.1_vae.safetensors" 200 &
  dl "$W/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$M/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" 5000 &
  wait
}
```

**캐릭터 / 일러스트 (5, 6, 7)**:
```bash
download_character() {
  # 베이스 모델 — CivitAI 또는 HF 미러
  # beautifulRealistic_asian_v7 (직접 URL 알아내거나 사용자에게 문의)
  dl "$HF/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors" "$M/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors" 700 &
  dl "$HF/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$M/clip_vision/ViT-H-14-laion2B-s32B-b79K.safetensors" 2000 &
  # FaceID SD1.5 (옵션)
  dl "$HF/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plus_sd15.bin" "$M/ipadapter/faceid.plus.sd15.bin" 100 &
  dl "$HF/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid_sd15.bin" "$M/ipadapter/faceid.sd15.bin" 80 &
  wait
}
```

**픽셀아트 (11)**:
```bash
download_pixelart() {
  # pixelArtDiffusionXL — CivitAI 또는 사용자 직접 업로드
  echo "⚠️ pixelArtDiffusionXL_spriteShaper.safetensors는 사용자가 직접 받아야 합니다."
}
```

### Step 5. 진행 상황 표시 + 완료 후 ComfyUI 재시작

```bash
# 다운로드 후 모델 인식
pkill -f "main.py" 2>/dev/null
sleep 2
cd /ComfyUI
nohup python main.py --listen 0.0.0.0 --port ${COMFYUI_PORT} > /workspace/comfy.log 2>&1 &
sleep 5
```

### Step 6. 완료 메시지

```
✅ 셋업 완료!

📦 다운로드: 8/8 (총 25.4GB)
📄 워크플로우: Han.json 사용 준비됨
🌐 ComfyUI: https://[POD-ID]-${COMFYUI_PORT}.proxy.runpod.net

이제 워크플로우 작업 시작하세요:
- 브라우저에서 ComfyUI 열기 → Workflows → Han.json 로드
- 또는 comfy-pilot MCP로 자동 빌드/실행:
  "한복 입은 여인이 정원에서 책 읽는 모습 만들어줘"
```

---

## 🤸 포즈 레퍼런스 (포즈 관련 요청 시 항상 참고)

**트리거 키워드**: "포즈", "앉아", "서있는", "포즈 참고", "이 포즈로", "포즈 맞춰", "관절", "스켈레톤", "포즈 편집"

### 🥇 1순위: github.com/a-lgil/pose-depot (포즈 라이브러리)

40+ 가지 검증된 포즈가 OpenPose/Canny/Depth/Normal 4가지 포맷으로 제공.

**API로 검색**:
```bash
curl -s "https://api.github.com/repos/a-lgil/pose-depot/contents/collections" | \
  python3 -c "import json,sys; [print(i['name']) for i in json.load(sys.stdin)]"
```

**컬렉션 예시**:
- `14F_Crossed_Legs_on_Floor` — 다리꼬고 바닥에 앉기 (한복에 좋음)
- `11F_Sitting_on_Stairs` — 계단에 앉기
- `16F_Sitting_and_Thinking` — 앉아서 생각
- `2F_Hand_on_Hip` — 손 허리에
- `7F_Glamorous_Greeting` — 우아한 인사
- `8F_Bed_Mirror_Selfie` — 거울 셀카
- (F = Female, M = Male)

**다운로드 + Pod에 저장**:
```bash
# 원하는 컬렉션의 OpenPose.png 받기
COLLECTION="14F_Crossed_Legs_on_Floor"
curl -sL "https://raw.githubusercontent.com/a-lgil/pose-depot/main/collections/$COLLECTION/OpenPose.png" \
  -o /workspace/comfyui/input/pose_sitting_crossed.png

# Canny/Depth도 같이 받으면
for type in Canny Depth Normal OpenPose; do
  curl -sL "https://raw.githubusercontent.com/a-lgil/pose-depot/main/collections/$COLLECTION/$type.png" \
    -o "/workspace/comfyui/input/pose_${COLLECTION}_${type}.png"
done
```

→ ComfyUI 워크플로우의 LoadImage 노드에서 선택 → ControlNetApplyAdvanced로 연결

### 🥈 2순위: openposes.com (포즈 직접 편집)

브라우저에서 스켈레톤 드래그로 원하는 포즈 만들기 → PNG 내보내기.

**트리거**: "포즈 직접 편집", "관절 조정", "스켈레톤 수정"

**사용 흐름**:
1. https://openposes.com 접속
2. 캔버스에서 관절 드래그하여 원하는 포즈
3. "Download as PNG" 클릭
4. 받은 PNG를 Pod에 업로드:
   ```bash
   # 로컬에서
   scp -P [PORT] pose_custom.png root@[POD_HOST]:/workspace/comfyui/input/
   ```
5. ComfyUI 워크플로우의 LoadImage 노드에서 사용

### 🥉 3순위: ComfyUI-openpose-editor (Pod 내장)

ComfyUI 캔버스 안에서 직접 포즈 편집 노드 사용.

**노드명**: `Openpose Editor`
**워크플로우 추가**: ComfyUI에서 더블클릭 → "Openpose Editor" 검색 → 노드 추가
→ ControlNetApplyAdvanced의 image 입력에 연결

### 포즈 워크플로우 통합 흐름

```
사용자: "한복 입은 여인이 다리 꼬고 앉은 포즈로 만들어줘"
   ↓
Claude 자동 진행:
   1. pose-depot에서 "Crossed_Legs_on_Floor" 검색
   2. OpenPose.png 다운로드 → /workspace/comfyui/input/
   3. Han.json 워크플로우의 LoadImage(pose) 노드에 그 이미지 지정
   4. KSampler 큐 실행
```

### 트리거 키워드별 자동 매칭

| 사용자 요청 | pose-depot 컬렉션 |
|------------|------------------|
| "앉은 포즈" / "앉아있는" | 14F_Crossed_Legs_on_Floor |
| "계단에 앉아" | 11F_Sitting_on_Stairs |
| "생각하는" / "고민" | 16F_Sitting_and_Thinking |
| "손 허리에" / "당당한" | 2F_Hand_on_Hip |
| "인사" / "공손한" | 7F_Glamorous_Greeting |
| "거울 보는" | 8F_Bed_Mirror_Selfie |
| "정면 서있는" | (Cover.png 보고 매칭) |
| "구체적 포즈 X" | pose-depot 리스트 전체 보여주고 사용자 선택 |

---

## 🛠 사용 가능한 도구

### Comfy-Pilot MCP (자동 등록됨)

`~/.claude/.mcp.json`에 user scope로 등록되어 모든 세션에서 사용 가능:
- `mcp__comfyui__get_workflow` — 캔버스 워크플로우 조회
- `mcp__comfyui__edit_graph` — 노드 추가/연결/수정
- `mcp__comfyui__run` — Queue 실행
- `mcp__comfyui__view_image` — 결과 이미지 표시
- `mcp__comfyui__get_status` — 큐/시스템 상태
- `mcp__comfyui__get_node_types` — 노드 검색

### Slash Commands

- `/comfy-setup [작업명]` — 추가 작업별 셋업
- 위 `Step 2-5` 흐름 다시 진행하고 싶을 때

---

## 🎨 자주 쓰는 작업 패턴 (참고)

### 한복 인물 (현대 하이패션)
```
모델: Juggernaut XL + hangbokXL_dangui (LoRA 0.65~0.75)
+ FaceID Plus v2 (얼굴 잠금)
+ IP-Adapter PLUS (의상 reference, weight_type: style and composition)
+ OpenPose ControlNet (포즈, strength 0.55~0.75)
+ FaceDetailer + HandDetailer (디테일)

Positive: "modern hanbok, contemporary korean fashion, high fashion editorial,
designer hanbok, minimalist silhouette, pastel jeogori, fashion photography"

Negative: "traditional palace hanbok, joseon dynasty costume, yukata, kimono,
bad anatomy, bad hands, blurry, watermark, deformed, ugly"

해상도: 832×1216 / Steps: 25 / CFG: 6.5 / dpmpp_2m + karras
```

### Wan2.2 비디오
```
high_noise + low_noise 14B fp8 듀얼 + Lightning LoRA × 2
카메라: Zoom In/Out/Pan Left/Right/Static
해상도: 480×272 (미리보기) → 832×480 (본 영상)
프레임: 81 (5초) / Steps: 4 / CFG: 1.0 / euler simple
```

---

## ⚠️ 핵심 주의사항

1. **ComfyUI 포트는 `${COMFYUI_PORT}`** (RunPod 콘솔 환경변수로 변경 가능, 기본 3000)
2. **Comfy-Pilot `.comfyui_url`** entrypoint가 자동 작성함 (포트 폴백 버그 우회)
3. **MCP는 user scope** (`~/.claude/.mcp.json`) — 다른 세션에서도 보임
4. **모델은 Network Volume에 영구 저장** — Pod 종료해도 유지
5. **Pod Stop = GPU 과금 중단** (Storage 월 $5~7만 유지)
6. **워크플로우는 entrypoint가 자동 복사** — `/opt/workflows-template/*.json` → `/workspace/comfyui/user/default/workflows/`
7. **다운로드 후 반드시 ComfyUI 재시작** (Manager 새로고침으론 인식 안 될 수도)

---

## 📝 사용자가 자주 묻는 것

### Q. 워크플로우 목록 보여줘
→ Step 2 다시 실행

### Q. "한복 작업하고 싶어"
→ 워크플로우 1 또는 2 선택 + Step 4의 `download_hanbok` 실행

### Q. "비디오 만들고 싶어"
→ 워크플로우 4 선택 + `download_wan22` 실행

### Q. "지금 모델 뭐 있어?"
→ `ls /workspace/comfyui/models/*/`

### Q. "디스크 부족해"
→ `df -h /workspace` + 가장 큰 모델 정리 안내

### Q. "Pod 종료하고 싶어"
→ "RunPod 대시보드 → My Pods → Stop. Storage($5~7/월)는 유지됩니다."
