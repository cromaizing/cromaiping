---
name: cromaiping-help
description: 크로마이핑 슬래시 명령어 전체 도움말. /cromaiping-help 또는 "크로마이핑 사용법" 같은 요청에 사용.
user_invocable: true
license: MIT
metadata:
  author: Cromaizing
  version: "1.0"
---

# cromaiping-help

크로마이핑 슬래시 명령어 도움말을 표시합니다.

## 사용법

```
/cromaiping-help
/크로마이핑-도움말
```

## 응답 예시

```
🎵 크로마이핑 명령어:

/cromaiping-status         현재 상태 (활성/음소거, 기본 팩, 볼륨)
/cromaiping-toggle         음소거 토글
/cromaiping-volume <0-100> 볼륨 변경
/cromaiping-use <팩>       이번 세션 팩 변경
/cromaiping-list           설치된 팩 목록
/cromaiping-help           이 도움말

한국어 별칭도 지원:
/크로마이핑-상태, /크로마이핑-음소거, /크로마이핑-볼륨,
/크로마이핑-팩, /크로마이핑-목록, /크로마이핑-도움말

홈페이지: https://cromaizing.com/cromaiping
```

## 추가 정보

터미널에서 사용 가능한 더 많은 기능:

```bash
cromaiping help                  # 전체 CLI 도움말
cromaiping packs list --registry # 레지스트리 팩 목록
cromaiping preview               # 사운드 미리듣기
cromaiping packs search <키워드> # 팩 검색
cromaiping packs install <팩>    # 팩 설치
```
