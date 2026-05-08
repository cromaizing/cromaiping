# 크로마이핑 (Cromaiping)

> AI가 작업 끝날 때마다 핑 — 한국 개발자를 위한 사운드 알림

## 🎯 한 줄 요약

Claude Code, Cursor, Codex 등 AI 코딩 도구가 작업을 끝내거나 입력을 기다릴 때 **사운드와 데스크톱 알림**으로 알려줍니다. 한국어 우선, 무료, 오픈소스.

---

## ⚡ 30초 설치

```bash
curl -fsSL https://cromaizing.com/cromaiping/install.sh | bash
```

설치 후 Claude Code 재시작하면 끝. 추가 설정 없이 바로 작동합니다.

> ⚠️ macOS / Linux / WSL2 지원. Windows는 v0.2 예정.

---

## 🤔 이런 적 있으신가요?

- AI한테 작업 시키고 다른 일 하다가 **20분 만에 돌아왔는데 5분 전에 끝나있었음**
- 권한 승인 기다리는데 모니터 안 보고 있어서 **계속 멈춰있었던 것** 모르고 지나감
- AI가 에러 토해냈는데 **모르고 다른 거 시킴**
- 회의 중인데 동료가 **"AI 응답 왔어?" 물어볼 때마다 화면 봐야 함**

크로마이핑이 해결합니다.

---

## ✨ 주요 기능

### 🔔 7가지 이벤트 인식

| 상황 | 사운드 |
|---|---|
| 세션 시작 | 환영 알림 |
| 작업 완료 | 성공 알림 |
| 오류 발생 | 경고 알림 |
| 입력 대기 (권한 승인) | 주의 알림 |
| 컨텍스트 리미트 | 한계 알림 |
| 너무 빠른 입력 (스팸) | 진정 알림 |

### 🎵 사운드팩 시스템

- 기본 팩 내장
- **CESP v1.0 호환** — 외부 325+ 팩 그대로 사용 가능
- 디렉토리별 다른 팩 (`*/work/* → 차분한 팩`, `*/personal/* → 재밌는 팩`)
- 팩 회전 모드 (랜덤/순환)

### 💬 한국어 슬래시 명령어

Claude Code 채팅에서 바로:
```
/cromaiping-status         현재 상태 확인
/cromaiping-toggle         음소거 토글
/cromaiping-volume 70      볼륨 변경
/cromaiping-use <팩>       팩 변경
/크로마이핑-상태           한국어도 OK
```

### 🔌 지원 도구

| 도구 | 상태 |
|---|---|
| Claude Code | ✅ Built-in |
| Cursor | 🚧 v0.3 예정 |
| Codex / Gemini CLI / Windsurf | 🚧 어댑터 v0.3 예정 |

### 🔐 프라이버시

- **완전 로컬 동작** — 클라우드 전송 0
- 텔레메트리 없음, 추적 없음
- 오픈소스 (MIT)
- 알림 데이터는 모두 ~/.claude/ 내부에만

---

## 🛠️ CLI 명령어

```bash
cromaiping status              # 상태 확인
cromaiping toggle              # 음소거 토글
cromaiping volume 70           # 볼륨 70%
cromaiping list                # 설치된 팩 목록
cromaiping preview             # 사운드 미리듣기
cromaiping use <팩이름>        # 팩 변경
cromaiping help                # 도움말
```

---

## ❓ 자주 묻는 질문

### Q. peon-ping과 뭐가 달라요?
A. peon-ping의 한국화 + 한국 시장 특화 버전입니다. 같은 CESP 표준을 쓰기 때문에 외부 사운드팩은 호환됩니다. 차이점:
- 한국어 UI/문서/슬래시 명령어
- 한국 개발자 환경 기준 트러블슈팅
- 카카오톡 알림, 한국어 TTS 등 한국 특화 기능 (v1.0 예정)
- cromaizing.com 생태계 통합 (스킬 마켓 연동, v1.0 예정)

### Q. 둘 다 깔아도 돼요?
A. 됩니다. 같은 이벤트에 둘 다 반응하니 사운드가 2번 울려요. 한쪽 음소거 추천:
```bash
peon pause             # peon-ping 음소거
cromaiping pause       # 또는 크로마이핑 음소거
```

### Q. 사운드를 직접 만들어도 되나요?
A. 네! CESP v1.0 표준대로 `openpeon.json` + `sounds/` 폴더만 있으면 됩니다. [팩 만들기 가이드](https://openpeon.com/create) 참고.

### Q. 회사에서 써도 되나요?
A. MIT 라이선스라 상업적 사용 가능합니다. 단, 사용하시는 사운드팩의 라이선스(특히 CC-BY-NC-4.0 등)는 별도로 확인하세요.

### Q. Linux/Windows에서도 동작해요?
A. macOS는 v0.1부터 완전 지원. Linux는 v0.2부터, Windows는 v0.3 예정입니다.

### Q. 회의 중에 사운드 안 울리게 할 수 있나요?
A. v0.2부터 자동 회의 감지 (마이크 사용 중 감지) 추가 예정입니다. 지금은 `cromaiping pause` / `resume`으로 수동 토글.

---

## 🛣️ 로드맵

### v0.1 (현재) ✅
- Claude Code 통합
- 기본 CLI + 슬래시 명령어
- CESP 호환 매니페스트
- 한국어 UI

### v0.2
- 외부 팩 자동 다운로더 (openpeon 레지스트리)
- 데스크톱 오버레이 알림 (macOS)
- 회의 자동 감지 (마이크 사용 시 음소거)
- 첫 자체 한국 사운드 팩

### v0.3
- Cursor / Codex / Gemini CLI 어댑터
- Homebrew tap 등록
- Windows PowerShell 지원

### v1.0
- **카카오톡 푸시 알림**
- **네이버 클로바 한국어 TTS**
- **cromaizing.com 통합** (계정 연동, 팩 마켓플레이스)
- MCP 서버 (모델이 직접 사운드 호출)

---

## 🔗 링크

- 🐙 **GitHub**: https://github.com/cromaizing/cromaiping
- 📦 **다운로드**: https://cromaizing.com/cromaiping/cromaiping-latest.tar.gz
- 💬 **커뮤니티**: https://cromaizing.com/community
- 📜 **CESP 표준**: https://openpeon.com/spec
- 🛠️ **참조 구현**: https://github.com/PeonPing/peon-ping

---

## 🏢 만든 곳

**우수에프앤씨 주식회사** · [cromaizing.com](https://cromaizing.com)
국내 최대 AI 커뮤니티

📧 woosu9859@gmail.com
