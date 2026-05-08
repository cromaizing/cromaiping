---
name: cromaiping-list
description: 설치된 크로마이핑 사운드 팩 목록을 보여줍니다. /cromaiping-list 또는 "어떤 팩들이 있어?" 같은 요청에 사용.
user_invocable: true
license: MIT
metadata:
  author: Cromaizing
  version: "1.0"
---

# cromaiping-list

설치된 사운드 팩 목록을 표시합니다.

## 사용법

```
/cromaiping-list
/크로마이핑-목록
```

## 어떻게 동작하는가

UserPromptSubmit 훅이 `~/.claude/hooks/cromaiping/packs/` 디렉토리를 스캔하여 각 팩의 매니페스트(`openpeon.json`)를 읽고 표시.

## 수동 처리

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/cromaiping/cromaiping.sh list
```

## 응답 예시

```
📦 설치된 팩:
  • karina — 카리나
  • cromaiping_default — 크로마이핑 기본 팩
  • teemo-kr — Teemo (Korean)

💡 더 많은 팩: 터미널에서 cromaiping packs list --registry
```

## 관련 작업

레지스트리에서 더 많은 팩 검색:
```bash
cromaiping packs list --registry
cromaiping packs search 한국
cromaiping packs install <팩이름>
```

팩 변경:
```
/cromaiping-use <팩이름>
```
