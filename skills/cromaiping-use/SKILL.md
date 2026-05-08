---
name: cromaiping-use
description: 이번 채팅 세션에 사용할 사운드 팩을 변경합니다. "카리나 음성으로 바꿔줘" 같은 요청이나 /cromaiping-use <팩이름> 명령에 사용하세요.
user_invocable: true
license: MIT
metadata:
  author: Cromaizing
  version: "1.0"
---

# cromaiping-use

이번 채팅 세션의 사운드 팩을 변경합니다.

## 어떻게 동작하는가

사용자가 `/cromaiping-use <팩이름>`을 입력하면 **UserPromptSubmit 훅**이 LLM에 도달하기 전에 가로채서 즉시 처리합니다:

1. 요청한 팩이 설치되어 있는지 검증
2. `.state.json`의 `session_packs`에 현재 세션 ID와 팩 매핑
3. 즉시 확인 메시지 반환 (토큰 0 사용)

훅 스크립트(`scripts/cmd-intercept.sh`)가 모든 작업을 처리합니다. 이 SKILL.md 파일은 `/` 자동완성 메뉴에 명령어가 표시되도록 하는 역할을 합니다.

## 사용법

```
/cromaiping-use karina
/cromaiping-use cromaiping_default
/cromaiping-use teemo-kr
```

또는 한국어 별칭:
```
/크로마이핑-팩 karina
```

훅이 미설치되었거나 실패한 경우, 아래 수동 처리를 LLM이 따라합니다.

## 수동 처리 (훅 실패 시)

훅이 명령어를 가로채지 못한 경우 다음 단계를 수행:

### 1. 팩 이름 추출

사용자 요청에서 팩 이름을 파싱. 일반적인 한국어 팩:
- `karina` — 카리나
- `cromaiping_default` — 기본 팩
- `teemo-kr` — 티모 한국어
- `sc2_scv_kr` — 스타크래프트 SCV 한국어

### 2. 설치된 팩 목록 확인

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh list
```

요청한 팩이 있는지 확인. 없으면 다음 명령어로 설치:

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh packs install <팩이름>
```

### 3. 세션 ID 가져오기

```bash
echo "$CLAUDE_SESSION_ID"
```

비어있으면 `"default"` 사용.

### 4. .state.json 수정

```bash
STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping/.state.json"
python3 -c "
import json, time
state = json.load(open('$STATE')) if __import__('os').path.exists('$STATE') else {}
state.setdefault('session_packs', {})['$CLAUDE_SESSION_ID'] = {'pack': '<팩이름>', 'last_used': time.time()}
json.dump(state, open('$STATE', 'w'), ensure_ascii=False, indent=2)
"
```

### 5. 또는 영구 변경 (모든 세션)

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh packs use <팩이름>
```

### 6. 사용자에게 확인

```
🎵 이번 세션 팩이 'karina'로 변경되었습니다.
```

## 에러 처리

- **팩을 찾을 수 없음**: 설치된 팩 목록 보여주고 사용자에게 선택 요청
- **세션 ID 없음**: 영구 변경(`packs use`)으로 fallback
- **파일 읽기/쓰기 오류**: 에러 메시지 보고 + `cromaiping packs list`로 디버그

## 사용 예시

```
사용자: 카리나 음성으로 바꿔줘
어시스턴트: [팩 목록 확인 → karina 발견]
어시스턴트: [세션 매핑 업데이트]
어시스턴트: 🎵 이번 세션 팩이 'karina'로 변경되었습니다.
```

## 관련 명령어

- `/cromaiping-list` — 설치된 팩 목록
- `/cromaiping-status` — 현재 활성 팩 확인
- `/cromaiping-toggle` — 음소거 토글
