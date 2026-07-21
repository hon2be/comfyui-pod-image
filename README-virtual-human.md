# 가상인간 파이프라인 · 사용 가이드

> 2026-07-22 확정. `configs/workflows/wan22_person_turnaround_api.json`, `flux_kontext_anime_style_api.json`, `flux_kontext_outfit_swap_api.json` 세 워크플로우를 조합.

## 전체 흐름

```
[원본 hero 사진]
     ↓
[선택 A] Flux Kontext 아니메 화풍 변환 → 아니메 hero
     ↓
[선택 B] Flux Kontext 옷 교체 (dual-ref · 옷 참조 이미지) → 옷 갈아입은 hero
     ↓
[최종] WAN 2.2 Fun Camera Static + 인물 회전 프롬프트 → 5초 360° turnaround mp4
```

## 워크플로우 파일

| 파일 | 목적 | 렌더 시간 | 필요 모델 |
|---|---|---|---|
| `wan22_person_turnaround_api.json` | 정면 사진 → 5초 360° turnaround | 8분 (RTX 4090) | Wan2.2 fun_camera high+low 14B · umt5 · wan VAE · ViT-H-14 CLIP vision |
| `flux_kontext_anime_style_api.json` | 실사 → 아니메 화풍 변환 | 80초 | Flux Kontext dev fp8 · t5xxl · clip_l · ae VAE |
| `flux_kontext_outfit_swap_api.json` | 옷 교체 (dual-ref) | 80초 | Flux Kontext dev fp8 · t5xxl · clip_l · ae VAE |

## 핵심 세팅 노트 (헛수고 방지)

### WAN 2.2 turnaround
- **ModelSamplingSD3(shift=8) 필수** · 없으면 배경 붕괴
- **KSamplerAdvanced 2단계** (KSampler 아님) · high 0-10step + low 10-끝step
- **CFG 3.5 · steps 20** · light2x LoRA 없이 full 렌더 (LoRA 붙이면 dynamics 손실)
- **camera_pose는 "Static"** · CW/ACW/Pan 은 카메라 자체 회전 (원치 않는 배경 왜곡 유발) · 인물 회전은 프롬프트로만
- 프롬프트: "she slowly rotates 360 degrees in place, camera does not move"
- 네거티브에 "camera shake, background change, industrial, machinery" 필수 (환각 방지)

### Flux Kontext 아니메 변환
- 단일 참조 (content 만) · ReferenceLatent 1개
- 프롬프트: "Transform the reference photograph into ... anime style illustration"
- 원본 pose/composition/outfit 언급하면 유지, 스타일만 바뀜

### Flux Kontext 옷 교체
- **두 참조 순차 주입**: content(인물) → ReferenceLatent → style(옷) → ReferenceLatent
- 프롬프트에 "first reference = 인물 유지, second reference = 옷 이식" 명시
- 옷 참조 이미지에 인물 함께 있으면 SK/브랜드 로고 negative 강화
- Kontext 는 dual-image reference 지원 (baked-in kontext_style_transfer.json 참고)

## Runner 스크립트

`~/.claude/skills/comfyui-remote/run_wan22_turnaround.py` — 로컬 CLI:

```bash
python3 ~/.claude/skills/comfyui-remote/run_wan22_turnaround.py \
  --hero /path/to/hero_front.png \
  --output /path/to/turnaround.mp4 \
  --seed 42 --camera Static
```

Kontext 아니메/옷교체는 파드에 워크플로우 업로드 후 `/prompt` 로 POST (스크립트 유사 구조 참고).

## 재사용 · 다음 세션

1. `python3 ~/.claude/skills/comfyui-remote/boot_ui_pod.py` — 파드 부팅 (2-4분)
2. WAN2.2 모델은 이미 볼륨(esjmoaksvu)에 있음 → 자동 스킵
3. 워크플로우 JSON은 `/opt/workflows-template/` 에 baked-in → 부팅 시 볼륨으로 복사
4. 로컬 이미지 업로드 → `/prompt` API 실행 → 결과 다운

## 예시 결과 (2026-07-22 인물1_20대_여성 검증)

- 실사 turnaround: 얼굴·의상·배경·조명 100% 유지 · 자연스러운 360° 회전
- 아니메 변환: 지브리/신카이 톤 · 셀 셰이딩 · 원본 pose/의상 구조 유지
- 옷 교체: hero 얼굴 유지 + 버건디 터틀넥 + 화이트 펜슬 스커트 정확 이식
