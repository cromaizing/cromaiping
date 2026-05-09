# `/cromaiping/create` 페이지 콘텐츠 (백엔드 통합용)

cromaizing.com 백엔드 개발자/CMS에 그대로 붙여넣을 수 있는 콘텐츠.

## 라우트 정보

```
URL: https://cromaizing.com/cromaiping/create
제목: 팩 만드는 법 · 크로마이핑 · cromaizing
SEO description: 크로마이핑 사운드팩 만들고 등록하는 방법을 5단계로 친절하게 안내합니다.
캐시: 1시간 (정적 콘텐츠)
인증: 불필요 (공개 페이지)
```

## 페이지 구조

```
1. Hero (배지 4개 + 큰 타이틀 + 설명 + 단계 목차)
2. Step 1: 사운드 파일 준비
3. Step 2: GitHub 저장소 만들기
4. Step 3: 매니페스트 작성 (자동 도구 추천)
5. Step 4: GitHub에 푸시
6. Step 5: cromaizing.com에 등록
7. FAQ (6개)
8. 최종 CTA
9. Footer
```

## 외부 링크 (페이지 내 anchor)

```
- /cromaiping/submit          → 팩 등록 폼
- /cromaiping/packs            → 팩 목록
- https://github.com/cromaizing/cromaiping  → 메인 레포
- https://github.com/new       → 새 GitHub 레포 만들기
- https://docs.github.com/ko/get-started/quickstart  → GitHub 한국어 가이드
```

## 디자인 토큰 (cromaizing.com과 일치)

```css
--background: #ffffff;
--foreground: #0a0a0a;
--muted: #f5f5f7;
--border: #e5e7eb;
--brand-violet: #7c3aed;
--brand-fuchsia: #d946ef;
--brand-coral: #fb7185;
```

## 추가 컴포넌트 (페이지 전용)

페이지 전용 스타일은 mockup HTML의 `<style>` 블록에 포함되어 있음:
- `.guide-hero` — 그라디언트 배경
- `.toc` — 단계 목차 (회색 박스)
- `.step-section` + `.step-num-large` — 단계별 큰 번호
- `.option-cards` — 4가지 방법 카드 (Step 1)
- `.code-block` — 코드 블록 (클릭 복사)
- `.file-tree` — 폴더 구조 시각화
- `.tip-box` / `.warn-box` — 노란 주의 + 보라 팁
- `.cta-final` — 끝의 그라디언트 CTA

cromaizing.com 디자인 시스템에 통합 시 이 스타일들을 컴포넌트로 추출 권장.

## 주의 사항

### 1. 코드 블록의 `bash <(curl ...)` 명령어
보안 우려할 사용자 있을 수 있음. 약관/문서에 다음 안내 권장:
- 명령어 검증 가능 (URL 직접 접근해서 스크립트 내용 확인)
- HTTPS 강제
- 또는 npm/pip 패키지로 대체 가능 (장기)

### 2. GitHub 저장소 Public 강제
사용자가 비공개 저장소 등록 시도 시 자동 검증에서 실패함.
이 안내가 페이지에 명시되어 있음 (Step 2).

### 3. 라이선스 고지
페이지에 다음 명시:
- ✅ AI TTS / 본인 녹음 / 라이선스 음원 / CC0
- ❌ 게임/영화/방송 음원 무단 추출 (warn-box로 강조)
- 약관 + 반복 위반자 정책 명시

## 관련 백엔드 작업

### 신규 라우트 추가 필요
```
GET /cromaiping/create
  - 정적 페이지 (캐시 가능)
  - 인증 불필요
```

### 검색엔진 최적화 (SEO)
- meta description 작성됨
- OG title / description 추가 권장
- sitemap.xml에 추가
- 한국 개발자 검색에 노출되도록 구글/네이버 검색 등록

### 분석 (선택)
- Google Analytics 또는 자체 분석으로 페이지 도달률 추적
- "Step X에서 이탈" 등 funnel 분석
- 등록 전환율 측정 (create → submit 클릭률)
