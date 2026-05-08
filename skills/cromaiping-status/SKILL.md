---
name: cromaiping-status
description: 크로마이핑 현재 상태(활성/음소거, 기본 팩, 볼륨, 알림 설정)를 보여줍니다. /cromaiping-status 또는 "크로마이핑 상태 보여줘" 같은 요청에 사용.
user_invocable: true
license: MIT
metadata:
  author: Cromaizing
  version: "1.0"
---

# cromaiping-status

크로마이핑 현재 상태를 표시합니다.

## 사용법

```
/cromaiping-status
/크로마이핑-상태
```

## 어떻게 동작하는가

UserPromptSubmit 훅이 `config.json`을 읽어 현재 설정을 반환합니다.

## 수동 처리

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh status
```

## 응답 예시

```
📊 상태: 활성 / 기본 팩: karina / 볼륨: 80% / 알림: 켜짐
```

## 관련 정보

표시되는 정보:
- **상태**: 활성/음소거 (`enabled` 필드)
- **기본 팩**: 현재 활성화된 사운드 팩
- **볼륨**: 0-100% (`volume` × 100)
- **알림**: 데스크톱 알림 켜짐/꺼짐
