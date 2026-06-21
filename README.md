# ComfyUI Pod Image (for RunPod)

honeybee의 ComfyUI 작업 환경을 통째로 포함한 Docker 이미지.

## ✨ 포함된 것

- ✅ ComfyUI 본체 (RunPod 공식 이미지 베이스)
- ✅ 커스텀 노드 11개 (IPAdapter, Impact-Pack, ControlNet aux, Comfy-Pilot 등)
- ✅ Claude Code (`@anthropic-ai/claude-code` 글로벌 설치)
- ✅ Comfy-Pilot MCP (Claude Code에서 ComfyUI 직접 제어)
- ✅ 사용자 워크플로우 JSON 18개 (한복, Wan2.2, 캐릭터 등)
- ✅ CLAUDE.md 자동 셋업 명세 (Pod 첫 부팅 시 모델 자동 다운로드)
- ❌ 모델 파일 (이미지 가볍게 — Network Volume에 자동 다운로드)

## 🚀 RunPod에서 사용

### 1) GitHub에 push (최초 1회)
```bash
cd ~/projects/comfyui-pod-image
git init
git add .
git commit -m "init"

# GitHub repo 생성 + push (gh CLI 필요)
gh repo create comfyui-pod-image --public --source=. --push
```

→ GitHub Actions가 자동으로 빌드 + ghcr.io 푸시 (20-30분)

### 2) RunPod에서 Pod 생성
```
Image: ghcr.io/[YOUR_USER]/comfyui-pod-image:latest
Container Disk: 30 GB
Volume Mount: /workspace (Network Volume 연결)
Expose HTTP: 3000

Environment Variables:
  CIVITAI_TOKEN=<your_token>     # 한복 작업 시 필수
  HF_TOKEN=<your_token>           # 선택 (다운로드 가속)
  COMFYUI_PORT=3000               # 기본값 (변경 가능)
```

### 3) Pod 부팅 후 SSH 접속
```bash
ssh root@[host] -p [port]
cd /workspace/work
claude
```

→ Claude Code가 `~/.claude/CLAUDE.md` 자동 읽고:
1. 환경 진단
2. 동봉된 워크플로우 18개 리스트 표시
3. 사용자가 원하는 워크플로우 선택
4. 그 워크플로우에 필요한 모델 자동 다운로드 (Network Volume에 영구 저장)
5. ComfyUI 재시작 + 작업 시작 안내

## 🔧 환경변수 (실행 시 변경 가능)

| 변수 | 기본값 | 용도 |
|------|--------|------|
| `COMFYUI_PORT` | `3000` | ComfyUI 리스닝 포트 |
| `COMFYUI_HOST` | `0.0.0.0` | 바인드 호스트 |
| `COMFY_PATH` | `/ComfyUI` | ComfyUI 본체 경로 |
| `VOLUME_PATH` | `/workspace/comfyui` | Network Volume 마운트 |
| `WORKING_DIR` | `/workspace/work` | Claude Code 시작 위치 |
| `WORKFLOWS_PATH` | `/workspace/comfyui/user/default/workflows` | 워크플로우 경로 |
| `HF_TOKEN` | (없음) | HuggingFace 토큰 |
| `CIVITAI_TOKEN` | (없음) | CivitAI 토큰 |

## 📁 폴더 구조

```
~/projects/comfyui-pod-image/
├── Dockerfile                          # 이미지 빌드 정의
├── .dockerignore
├── .github/workflows/build.yml         # GitHub Actions
├── scripts/
│   └── entrypoint.sh                   # Pod 부팅 시 자동 실행
├── configs/
│   ├── claude/
│   │   ├── CLAUDE.md                   # Claude 자동 셋업 지시서
│   │   ├── settings.json               # Claude 설정
│   │   └── commands/                   # slash commands
│   └── workflows/                      # 워크플로우 JSON 18개
└── README.md
```

## 🔄 워크플로우 추가/수정

새 워크플로우 추가하려면:
```bash
# 로컬 ComfyUI에서 작업한 워크플로우를 이미지에 포함
cp ~/projects/ComfyUI/user/default/workflows/new_workflow.json \
   ~/projects/comfyui-pod-image/configs/workflows/

# CLAUDE.md 워크플로우 리스트에 추가 (어떤 모델 필요한지 매핑)
nano configs/claude/CLAUDE.md

# Git push → 자동 재빌드
git add . && git commit -m "add new_workflow" && git push
```

## 💰 비용

| 항목 | 비용 |
|------|------|
| Network Volume 100GB | $5~7/월 |
| Pod (A40 사용 시) | $0.39/hr |
| 첫 셋업 (모델 다운로드 30분) | ~$0.20 |
| 일상 1시간 작업 | ~$0.40 |

## ⚠️ 주의사항

- **Pod Stop ≠ Pause** — Stop만 GPU 과금 중단
- **Network Volume 미사용 시 Pod 종료하면 모델 사라짐**
- **CIVITAI_TOKEN 없으면 한복 모델 다운로드 실패** — civitai.com에서 발급
- **Comfy-Pilot은 자동으로 user scope MCP로 등록됨** — claude 실행 시 즉시 사용 가능

## 🔗 관련

- 로컬 환경 dump: `~/projects/safegen/pod-context/POD_CONTEXT.md`
- 자동 셋업 명령: `~/.claude/commands/comfy-setup.md`
- RunPod 가이드: `~/.claude/commands/comfyui.md` (별첨)
