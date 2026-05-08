---
name: cromaiping-volume
description: 크로마이핑 볼륨을 변경합니다 (0-100). /cromaiping-volume 70 또는 "볼륨 50으로 바꿔줘" 같은 요청에 사용.
user_invocable: true
license: MIT
metadata:
  author: Cromaizing
  version: "1.0"
---

# cromaiping-volume

크로마이핑 사운드 재생 볼륨을 조회/변경합니다.

## 사용법

```
/cromaiping-volume          # 현재 볼륨 확인
/cromaiping-volume 70       # 70%로 설정
/크로마이핑-볼륨 50         # 한국어 별칭
```

## 어떻게 동작하는가

UserPromptSubmit 훅이 `config.json`의 `volume` 필드를 변경합니다 (0.0-1.0 범위).
입력값은 0-100 또는 0.0-1.0 모두 지원하며, 100 초과시 자동 정규화.

## 수동 처리

```bash
# 조회
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh volume

# 설정
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh volume 70
```

## 응답 예시

```
🔊 볼륨이 70%로 설정되었습니다.
```

## 사용 팁

- **회의/통화 중**: 30-40% (배경 알림 정도)
- **집중 작업**: 50-70% (확실히 들리지만 방해 안 됨)
- **카페 등 시끄러운 곳**: 80-100% (외부 소음 대응)
- **완전 무음**: `cromaiping pause` 추천 (볼륨 0보다 깔끔)
