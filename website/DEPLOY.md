# 크로마이핑 웹사이트 배포 가이드

cromaizing.com에 크로마이핑 페이지를 올리는 방법.

## 📦 업로드할 파일 (3종)

| 파일 | 업로드 위치 | 용도 |
|---|---|---|
| `dist/cromaiping-latest.tar.gz` | `https://cromaizing.com/cromaiping/cromaiping-latest.tar.gz` | 최신 배포본 (always-latest 링크) |
| `dist/cromaiping-0.1.0.tar.gz` | `https://cromaizing.com/cromaiping/cromaiping-0.1.0.tar.gz` | 버전별 아카이브 |
| `install.sh` | `https://cromaizing.com/cromaiping/install.sh` | 설치 one-liner 타겟 |

## 🌐 랜딩 페이지

`website/index.html` 파일이 완성된 한 페이지 사이트입니다.

### 옵션 A: 정적 HTML 그대로 호스팅
- `index.html`을 그대로 `https://cromaizing.com/cromaiping/index.html` 에 업로드
- CDN/호스팅이 정적 파일 서빙 지원하면 끝

### 옵션 B: 기존 CMS에 콘텐츠 이식
`website/landing.md` 마크다운을 cromaizing.com CMS에 복사/붙여넣기. CSS는 사이트 글로벌 스타일에 맞게 조정.

## 🔄 새 버전 릴리스 절차

```bash
# 1. 코드 수정 후 VERSION 업데이트
echo "0.2.0" > VERSION

# 2. tarball 빌드
bash scripts/build-tarball.sh

# 3. 3개 파일 업로드 (기존 방식대로)
#    - dist/cromaiping-latest.tar.gz
#    - dist/cromaiping-0.2.0.tar.gz  
#    - install.sh (변경된 경우만)

# 4. git tag + push
git tag v0.2.0 && git push origin v0.2.0
```

## 🧪 설치 one-liner 테스트

업로드 후 다른 머신에서:

```bash
curl -fsSL https://cromaizing.com/cromaiping/install.sh | bash
```

또는 dry-run (다운로드만):
```bash
curl -fsSL https://cromaizing.com/cromaiping/install.sh -o /tmp/cromaiping-install.sh
less /tmp/cromaiping-install.sh   # 내용 확인
bash /tmp/cromaiping-install.sh   # 실행
```

## 🔐 보안 권장사항

1. **HTTPS 필수** — `curl | bash` 패턴은 HTTPS 아니면 위험
2. **체크섬 게시** — 각 tarball의 SHA-256을 사이트에 명시 권장
   ```bash
   shasum -a 256 dist/cromaiping-0.1.0.tar.gz
   ```
3. **install.sh URL 픽스** — install.sh 내 `TARBALL_URL`이 우리 도메인 가리키는지 매번 확인

## 📊 게시할 SEO 메타데이터 (이미 index.html에 포함)

- Title: 크로마이핑 (Cromaiping) — AI 코딩 도구용 한국형 사운드 알림
- Description: Claude Code, Cursor, Codex 등 AI 코딩 도구가 작업을 끝낼 때 사운드와 알림으로 알려줍니다.
- OG image: 직접 만들어야 함 (1200x630 추천)

## 🎨 디자인 유의사항

- cromaizing.com 메인 사이트 스타일에 맞추기
- 다크 테마 기준 (현재 index.html 기반)
- 한글 폰트 Pretendard 또는 SF Pro Korean
- 모바일 반응형 (이미 구현됨)
