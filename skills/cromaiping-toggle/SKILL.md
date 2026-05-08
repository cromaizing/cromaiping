---
name: cromaiping-toggle
description: 크로마이핑 사운드 알림을 음소거/활성화 토글합니다. /cromaiping-toggle 또는 "사운드 꺼줘"/"음소거" 같은 요청에 사용.
user_invocable: true
license: MIT
metadata:
  author: Cromaizing
  version: "1.0"
---

# cromaiping-toggle

크로마이핑 사운드를 음소거 ↔ 활성화 토글합니다.

## 사용법

```
/cromaiping-toggle
/크로마이핑-음소거
/크로마이핑-활성
```

## 어떻게 동작하는가

UserPromptSubmit 훅(`scripts/cmd-intercept.sh`)이 명령어를 가로채서 `config.json`의 `enabled` 필드를 토글합니다.

## 수동 처리 (훅 실패 시)

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh toggle
```

또는 명시적 음소거/활성화:

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh pause   # 음소거
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh resume  # 활성화
```

## 사용 시나리오

- 회의/통화 중 사운드 일시 끄기
- 집중하고 싶을 때
- 야간 작업 시 무음 모드

## 응답 예시

```
🔇 크로마이핑 음소거됨
```
또는
```
🔊 크로마이핑 활성화됨
```
