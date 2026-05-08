# 크로마이핑 팩 마켓플레이스 백엔드 — cromaizing.com 통합 가이드

이 폴더는 cromaizing.com 백엔드 개발자가 받아서 통합할 수 있는 **명세 + 모듈 + mockup** 모음입니다.

## 📁 폴더 구조

```
backend/
├── README.md              # 이 파일
├── db/                    # DB 스키마 + 마이그레이션
│   ├── schema.sql
│   └── migrations/
│       └── 001_create_pack_tables.sql
├── api/                   # API 명세
│   ├── openapi.yaml       # OpenAPI 3.0 스펙
│   ├── routes.md          # 한국어 라우트 설명
│   └── examples/          # 요청/응답 예시 JSON
├── lib-node/              # Node.js 검증 라이브러리 (재사용 가능)
│   ├── github.js          # GitHub URL 파서 + 다운로더
│   ├── manifest.js        # CESP 매니페스트 검증
│   ├── magic-bytes.js     # 오디오 매직바이트 검증
│   ├── validator.js       # 통합 검증 (위 3개 묶음)
│   ├── post-template.js   # 자동 게시글 본문 생성
│   └── registry.js        # registry.json 빌더
├── templates/             # 본문 템플릿
│   └── post-body.md.tmpl  # 게시글 마크다운 템플릿
├── policy/                # 약관 + 정책
│   └── terms-section-ko.md  # 회원가입 약관에 추가할 콘텐츠 정책 절
└── frontend-mockup/       # 프론트엔드 화면 mockup (참고용 HTML)
    ├── pack-list.html       # 4컬럼 목록
    ├── pack-detail.html     # 게시글 상세
    └── submit-form.html     # 등록 폼
```

## 🎯 통합 흐름 (cromaizing.com 개발자 관점)

### 1. DB 마이그레이션 적용
```bash
psql -f backend/db/migrations/001_create_pack_tables.sql
# 또는 ORM 마이그레이션으로 변환
```

### 2. Node.js 라이브러리 통합
```bash
cp -r backend/lib-node/* your-backend/lib/cromaiping/
npm install axios tar-stream
```

또는 Next.js API routes에서 import:
```js
// pages/api/cromaiping/packs/preview.js
import { validatePackFromGithub } from '../../../lib/cromaiping/validator';
```

### 3. 라우트 구현 (Express 또는 Next.js)
- `api/openapi.yaml` 명세 따라 6개 엔드포인트 구현
- `lib-node/` 라이브러리 그대로 활용

### 4. 약관 업데이트
- `policy/terms-section-ko.md` 절을 회원가입 약관에 추가

### 5. 프론트엔드 (cromaizing.com 디자인 시스템 적용)
- `frontend-mockup/` HTML 참고
- 기존 게시판 컴포넌트 재활용 + 4컬럼 + 미리듣기 버튼

## 🔑 핵심 결정사항 (이미 합의됨)

| 항목 | 결정 |
|---|---|
| 인증 모델 | 로그인 사용자만 (회원가입 시 핸드폰 인증으로 신원 확보) |
| 등록 시 추가 검증 | ❌ 없음 (즉시 등록) |
| 약관 동의 | 회원가입 시 1회 (등록 시 추가 X) |
| 호스팅 | ❌ 안 함 (인덱서 모델, 다운로드는 GitHub 원본) |
| 사후 처리 | 신고 시스템 (24-48h SLA) |
| 등록 흐름 | 3단계 (URL 입력 → 자동 검증 → 등록) |
| 게시판 통합 | cromaizing.com 기존 게시판 활용 |

## 📊 의존성 (Node.js 기준)

### 필수
- `axios` — GitHub API 호출
- `tar-stream` — tarball 압축 해제 (또는 `node-tar`)
- `node:crypto` — SHA-256 (Node 내장)

### 선택
- `octokit` — GitHub API 더 편하게 (옵션)

## 🧪 테스트

각 모듈은 단독 테스트 가능. `lib-node/` 안에 함수 단위로 분리되어 있어서 mocha/jest로 단위 테스트 작성 권장.

## 🔗 참고

- CESP v1.0 표준: https://openpeon.com/spec
- 크로마이핑 메인: https://github.com/cromaizing/cromaiping
- cromaiping.sh의 검증 로직 (bash 원본): `../cromaiping.sh`의 `download_pack()` 함수
