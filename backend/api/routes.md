# API 라우트 한국어 가이드

OpenAPI 스펙은 `openapi.yaml` 참조. 여기는 개발자용 한국어 설명.

## 인증

모든 보호 엔드포인트는 cromaizing.com 기존 **세션 쿠키**로 인증.
- 로그인 = 회원 = 핸드폰 인증 완료자
- 별도 추가 인증 X

## 라우트 6개 (필수 MVP)

### 1. 검증 + 미리보기
```
POST /api/cromaiping/packs/preview
Auth: 로그인
Body: { "github_url": "https://github.com/user/my-pack" }
```

흐름:
1. `lib-node/validator.js` 의 `validatePackFromGithub()` 호출
2. 결과 반환 (성공: 메타데이터 + 미리듣기 URL / 실패: 에러 목록)

### 2. 등록 (즉시 게시글 생성)
```
POST /api/cromaiping/packs/submit
Auth: 로그인
Body: { "github_url": "..." }
```

흐름:
1. preview와 동일 검증
2. 트랜잭션 시작
   - posts 테이블 INSERT (자동 본문, 자동 제목, 카테고리=cromaiping)
   - pack_metadata 테이블 INSERT
3. 트랜잭션 커밋
4. registry.json 캐시 invalidate (또는 webhook)
5. 게시글 URL 반환

### 3. 목록 (4컬럼 게시판)
```
GET /api/cromaiping/packs/list
Query: q, lang, tag, sort, page, limit
```

쿼리 예시:
```sql
SELECT
  pm.name,
  pm.display_name,
  pm.created_at,
  u.username AS submitter_username,
  pm.preview_sound_url,
  pm.download_count,
  pm.language
FROM pack_metadata pm
JOIN users u ON u.id = pm.submitter_user_id
WHERE pm.status = 'active'
  AND ($1::text IS NULL OR pm.display_name ILIKE '%' || $1 || '%')
  AND ($2::text IS NULL OR pm.language = $2)
  AND ($3::text IS NULL OR pm.tags @> jsonb_build_array($3))
ORDER BY
  CASE WHEN $4 = 'popular' THEN pm.download_count END DESC NULLS LAST,
  CASE WHEN $4 = 'name' THEN pm.name END ASC NULLS LAST,
  pm.created_at DESC
LIMIT $5 OFFSET $6;
```

### 4. 개별 팩 상세
```
GET /api/cromaiping/packs/:name
```

게시글 본문 + 카테고리별 전체 사운드 미리듣기 URL 반환.
조회수 증가는 별도 트랜잭션으로 (UPDATE pack_metadata SET view_count = view_count + 1).

### 5. 레지스트리 (CLI용)
```
GET /api/cromaiping/registry.json
Cache: CDN 5분
```

`lib-node/registry.js` 의 `buildRegistryJson()` 호출 → JSON 반환.
크로마이핑 CLI의 `fetch_registry()`가 이 엔드포인트에서 받음.

### 6. 신고
```
POST /api/cromaiping/packs/:name/report
Auth: 로그인 (또는 익명 허용 — DMCA용)
Body: { "reason": "copyright", "description": "...", "rightsholder_email": "..." }
```

흐름:
1. `pack_reports` 테이블 INSERT
2. 관리자에게 알림 (이메일 또는 Slack)
3. 누적 신고 5건 이상이면 자동 status='frozen' (선택)

## 관리자 라우트 (Phase 2)

### 신고 큐
```
GET /api/cromaiping/admin/reports?status=open
Auth: 관리자
```

### 팩 비공개
```
POST /api/cromaiping/admin/packs/:name/freeze
Auth: 관리자
```

### 팩 영구 제거
```
DELETE /api/cromaiping/admin/packs/:name
Auth: 관리자
```

## 레이트 리밋

| 엔드포인트 | 제한 |
|---|---|
| `/preview` | 분당 30회 |
| `/submit` | 일당 5팩, 시간당 2팩 |
| `/report` | 시간당 10회 |
| `/registry.json` | 무제한 (캐시) |

## 에러 코드 표준

```json
{
  "error": "INVALID_MANIFEST",
  "message": "한국어 설명 메시지",
  "field": "categories",
  "details": { ... }
}
```

코드 목록:
- `URL_INVALID` - GitHub URL 형식 잘못됨
- `REPO_NOT_FOUND` - GitHub repo 접근 불가
- `MANIFEST_MISSING` - openpeon.json 없음
- `MANIFEST_INVALID` - CESP 매니페스트 형식 위반
- `NAME_INVALID` - 팩 이름 형식 위반
- `NAME_DUPLICATE` - 이미 등록된 이름
- `SIZE_LIMIT_EXCEEDED` - 50MB 초과 또는 파일 1MB 초과
- `INVALID_AUDIO` - 오디오 파일 매직바이트 검증 실패
- `RATE_LIMIT_EXCEEDED` - 레이트 리밋 초과
- `UNAUTHORIZED` - 로그인 필요
- `FORBIDDEN` - 권한 없음 (남의 팩 삭제 시도 등)
