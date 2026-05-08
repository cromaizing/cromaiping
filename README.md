# 크로마이핑 (Cromaiping)

> AI 코딩 도구용 한국형 사운드 알림 시스템

Claude Code, Cursor, Codex 등 AI 코딩 도구가 작업을 완료하거나 입력을 기다릴 때 사운드와 데스크톱 알림을 띄워줍니다. **CESP v1.0 호환**으로 기존 사운드팩 생태계도 그대로 사용할 수 있습니다.

🌐 https://cromaizing.com/cromaiping

---

## ✨ 특징

- 🎵 **즉시 동작**: Claude Code 훅에 자동 등록, 설치 후 바로 사용
- 🇰🇷 **한국어 우선**: 한국어 알림, 한국어 슬래시 명령어, 한국어 문서
- 🔌 **CESP 호환**: openpeon.com 표준 그대로 사용, 325+개 외부 팩 호환
- 🎛️ **세밀한 제어**: 카테고리별 토글, 볼륨, 팩 회전, 경로별 다른 팩
- 🪶 **가벼움**: 약 500줄 bash + Python, 외부 의존성 최소

---

## 🚀 설치

### 🍺 Homebrew (macOS / Linux 추천)
```bash
brew install cromaizing/tap/cromaiping
```

### ⚡ Curl one-liner (모든 플랫폼)
```bash
# cromaizing.com 호스팅 (브랜드 도메인)
curl -fsSL https://cromaizing.com/cromaiping/install.sh | bash

# 또는 GitHub Releases (백업)
curl -fsSL https://github.com/cromaizing/cromaiping/releases/latest/download/install.sh | bash
```

### 📦 Git 클론 (개발자용)
```bash
git clone https://github.com/cromaizing/cromaiping
cd cromaiping
bash install.sh
```

설치하면 `~/.claude/hooks/cromaiping/`에 파일이 들어가고, `~/.claude/settings.json`에 훅이 자동 등록됩니다. Claude Code 재시작하면 바로 동작합니다.

---

## 🎮 사용법

### CLI

```bash
cromaiping status              # 상태 확인
cromaiping toggle              # 음소거 토글
cromaiping volume 70           # 볼륨 70%로 설정
cromaiping use cromaiping_default  # 팩 변경
cromaiping list                # 설치된 팩 목록
cromaiping preview             # 사운드 미리듣기
cromaiping preview task.error  # 특정 카테고리 미리듣기
```

### Claude Code 채팅에서 슬래시 명령어

```
/cromaiping-status            현재 상태
/cromaiping-toggle            음소거 토글
/cromaiping-volume 70         볼륨 변경
/cromaiping-use <팩이름>      이번 세션 팩 변경
/cromaiping-list              팩 목록
/cromaiping-help              도움말
```

한국어 별칭도 지원합니다: `/크로마이핑-팩`, `/크로마이핑-음소거`, `/크로마이핑-상태`

---

## 🎼 이벤트 → 사운드 매핑

| Claude Code 이벤트 | CESP 카테고리 | 의미 |
|---|---|---|
| SessionStart | `session.start` | 세션 시작 |
| Stop | `task.complete` | 작업 완료 |
| UserPromptSubmit (rapid) | `user.spam` | 너무 빠른 입력 (3+ in 10초) |
| PermissionRequest | `input.required` | 권한 요청 |
| PostToolUseFailure (Bash) | `task.error` | Bash 실패 |
| PreCompact | `resource.limit` | 컨텍스트 압축 시작 |

---

## ⚙️ 설정 파일

위치: `~/.claude/hooks/cromaiping/config.json`

```json
{
  "default_pack": "cromaiping_default",
  "volume": 0.5,
  "enabled": true,
  "desktop_notifications": true,
  "categories": {
    "session.start": true,
    "task.complete": true,
    "task.error": true,
    "input.required": true,
    "resource.limit": true,
    "user.spam": true
  },
  "path_rules": [
    { "pattern": "*/work/*", "pack": "professional_pack" },
    { "pattern": "*/personal/*", "pack": "fun_pack" }
  ]
}
```

---

## 📦 팩 만들기

CESP v1.0 표준을 따릅니다. `packs/<팩이름>/openpeon.json` 매니페스트와 `sounds/` 폴더만 있으면 됩니다.

```
my-pack/
├── openpeon.json
└── sounds/
    ├── hello.wav
    └── done.wav
```

매니페스트 예시는 [`packs/cromaiping_default/openpeon.json`](packs/cromaiping_default/openpeon.json) 참고.

---

## 🗂️ 디렉토리 구조

```
cromaiping/
├── VERSION
├── cromaiping.sh             # 메인 훅 핸들러 + CLI
├── config.json               # 기본 설정
├── install.sh                # 인스톨러 (로컬 + 원격 자동 감지)
├── uninstall.sh              # 제거 스크립트
├── LICENSE                   # MIT
├── scripts/
│   ├── cmd-intercept.sh      # 슬래시 명령어 처리
│   ├── gen-placeholder-sounds.sh  # 기본 사운드 생성
│   └── build-tarball.sh      # 배포본 빌드
├── adapters/                 # 다른 IDE용 (예정)
├── packs/
│   └── cromaiping_default/
│       ├── openpeon.json     # CESP v1.0 매니페스트
│       └── sounds/           # gitignored (install 시 생성)
└── website/                  # cromaizing.com 배포 자산
    ├── index.html
    ├── landing.md
    └── DEPLOY.md
```

---

## 🔌 지원 도구 (v0.1.2 — 11개)

| 도구 | 셋팅 위치 | 비고 |
|---|---|---|
| Claude Code (터미널/데스크톱) | `~/.claude/settings.json` (자동) | 8개 이벤트 + 슬래시 명령어 |
| Cursor | `~/.cursor/hooks.json` | python3 사용 (jq 불필요) |
| OpenAI Codex | `~/.codex/config.toml` | notify 형식 |
| Gemini CLI | `~/.gemini/settings.json` | hook 4개 매처 |
| Windsurf | `~/.codeium/windsurf/hooks.json` | Cascade hooks |
| Kiro | `~/.kiro/agents/cromaiping.json` | camelCase 이벤트 매핑 |
| Rovo Dev (Atlassian) | `~/.rovodev/config.yml` | CLI 인자 형식 |
| OpenClaw | skill 내부 호출 | 다양한 이벤트명 지원 |
| DeepAgents | `~/.deepagents/hooks.json` | dotted event 매핑 |
| Google Antigravity | 백그라운드 watcher | fswatch / inotify-tools 필요 |
| Kimi Code (Moonshot) | macOS LaunchAgent / Linux nohup | --install 자동 셋업 |
| OpenCode | TypeScript 플러그인 | 자동 설치 스크립트 |

각 어댑터의 자세한 셋업은 `adapters/<이름>.sh` 헤더 주석 참고.

---

## 🛣️ 로드맵

### v0.1.2 (현재) ✅
- [x] Claude Code 훅 통합 (터미널 + 데스크톱 앱)
- [x] CLI + 한국어 슬래시 명령어 6개
- [x] CESP v1.0 호환 매니페스트
- [x] 외부 팩 다운로더 (cromaiping packs install)
- [x] 카리나 한국어 음성팩 기본 활성화
- [x] **11개 IDE 어댑터** (Cursor / Codex / Gemini / Windsurf / Kiro / Rovo Dev / OpenClaw / DeepAgents / Antigravity / Kimi / OpenCode)
- [x] Homebrew + curl one-liner 배포

### v0.2 (예정)
- [ ] 데스크톱 오버레이 알림 (macOS)
- [ ] 회의 자동 감지 (마이크 사용 시 음소거)
- [ ] 자체 한국 팩 다양화 (5~10개)
- [ ] 외부 팩 카탈로그 확장

### v0.3
- [ ] Windows 네이티브 지원
- [ ] MCP 서버
- [ ] 팩 회전 모드 향상

### v1.0
- [ ] 카카오톡/슬랙 알림 통합
- [ ] 네이버 클로바 한국어 TTS
- [ ] cromaizing.com 통합 (계정 연동, 팩 마켓)
- [ ] MCP 서버

---

## 📜 라이선스

MIT License

크로마이핑은 [peon-ping](https://github.com/PeonPing/peon-ping)의 아키텍처를 참조하여 한국 사용자를 위해 새로 작성되었습니다. CESP 표준은 OpenPeon 프로젝트의 공개 표준입니다.

---

## 🏢 만든 곳

**우수에프앤씨 주식회사** · [cromaizing.com](https://cromaizing.com)
국내 최대 AI 커뮤니티

📧 woosu9859@gmail.com
