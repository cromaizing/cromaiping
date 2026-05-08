#!/bin/bash
# 크로마이핑 릴리즈 자동화 스크립트
# 사용자가 한 번만 실행하면 Public 전환 + Release + Homebrew tap 까지 모두 처리
#
# 사용법:
#   bash scripts/publish-release.sh [버전]
#   기본 버전: VERSION 파일에서 읽음
set -euo pipefail

GREEN="\033[32m"; BLUE="\033[34m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${BLUE}ℹ${RESET}  $*"; }
ok()    { echo -e "${GREEN}✓${RESET}  $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET}  $*"; }
err()   { echo -e "${RED}✗${RESET}  $*" >&2; }

# GH_TOKEN 우회 (keyring 사용)
unset GH_TOKEN

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${1:-$(cat VERSION | tr -d '[:space:]')}"
REPO="cromaizing/cromaiping"
TAP_REPO="cromaizing/homebrew-tap"

cat <<BANNER
╔══════════════════════════════════════════╗
║   크로마이핑 릴리즈 출판                 ║
╠══════════════════════════════════════════╣
║   버전:      v$VERSION
║   메인 레포: $REPO
║   Tap 레포:  $TAP_REPO
╚══════════════════════════════════════════╝
BANNER
echo ""

# 인증 확인
if ! gh auth status >/dev/null 2>&1; then
  err "gh CLI 인증 필요. 'gh auth login' 먼저 실행해주세요."
  exit 1
fi
ok "gh CLI 인증 확인됨"

# ─────────────────────────────────────────────
# 1. 메인 레포 Public 전환
# ─────────────────────────────────────────────
info "1단계: 메인 레포 Public 전환 확인"
VISIBILITY=$(gh repo view "$REPO" --json visibility --jq .visibility 2>/dev/null || echo "UNKNOWN")
if [ "$VISIBILITY" = "PRIVATE" ]; then
  warn "현재 Private. Public으로 전환합니다..."
  read -p "정말 Public으로 전환하시겠습니까? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    err "취소됨"
    exit 1
  fi
  gh repo edit "$REPO" --visibility public --accept-visibility-change-consequences
  ok "메인 레포 Public 전환 완료"
else
  ok "이미 Public ($VISIBILITY)"
fi

# ─────────────────────────────────────────────
# 2. tarball 빌드
# ─────────────────────────────────────────────
info "2단계: 배포 tarball 빌드"
bash scripts/build-tarball.sh
TARBALL="dist/cromaiping-${VERSION}.tar.gz"
TARBALL_LATEST="dist/cromaiping-latest.tar.gz"
[ -f "$TARBALL" ] || { err "tarball 빌드 실패"; exit 1; }

SHA256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
ok "SHA-256: $SHA256"

# ─────────────────────────────────────────────
# 3. Git 태그 + 푸시
# ─────────────────────────────────────────────
info "3단계: Git 태그 v${VERSION} 생성"
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
  warn "태그 v${VERSION} 이미 존재 (스킵)"
else
  git tag -a "v${VERSION}" -m "v${VERSION} 릴리즈"
  git push origin "v${VERSION}"
  ok "태그 푸시 완료"
fi

# ─────────────────────────────────────────────
# 4. GitHub Release 생성
# ─────────────────────────────────────────────
info "4단계: GitHub Release 생성"
if gh release view "v${VERSION}" --repo "$REPO" >/dev/null 2>&1; then
  warn "Release v${VERSION} 이미 존재 — 자산만 업데이트합니다"
  gh release upload "v${VERSION}" "$TARBALL" "$TARBALL_LATEST" install.sh --clobber --repo "$REPO"
else
  RELEASE_NOTES=$(cat <<NOTES
## 🎉 크로마이핑 v${VERSION} 첫 번째 정식 릴리즈

AI 코딩 도구(Claude Code, Cursor, Codex 등)가 작업을 끝낼 때 사운드와 알림으로 알려주는 한국형 도구.

### ⚡ 설치

\`\`\`bash
# Homebrew (macOS / Linux 추천)
brew install cromaizing/tap/cromaiping

# 또는 Curl one-liner
curl -fsSL https://github.com/cromaizing/cromaiping/releases/latest/download/install.sh | bash
\`\`\`

### ✨ 주요 기능
- Claude Code 8개 이벤트 훅 (SessionStart, Stop, PermissionRequest 등)
- CESP v1.0 호환 사운드 팩 (외부 325+ 팩 호환)
- 한국어 슬래시 명령어 (\`/크로마이핑-상태\` 등)
- 외부 팩 자동 다운로더 (\`cromaiping packs install <name>\`)
- 카리나 음성 팩 내장 (한국어, 6개 카테고리)
- 멀티 플랫폼 (macOS / Linux / WSL2)

### 📜 라이선스
MIT (코드) · CC-BY-NC-4.0 (카리나 음성팩)

### 🏢 만든 곳
[우수에프앤씨 주식회사](https://cromaizing.com) — 국내 최대 AI 커뮤니티
NOTES
  )
  gh release create "v${VERSION}" \
    --repo "$REPO" \
    --title "v${VERSION} — 첫 번째 릴리즈" \
    --notes "$RELEASE_NOTES" \
    "$TARBALL" "$TARBALL_LATEST" install.sh
  ok "Release 생성 완료"
fi

RELEASE_URL="https://github.com/${REPO}/releases/tag/v${VERSION}"
TARBALL_URL="https://github.com/${REPO}/releases/download/v${VERSION}/cromaiping-${VERSION}.tar.gz"

# ─────────────────────────────────────────────
# 5. Homebrew tap 레포 (없으면 생성)
# ─────────────────────────────────────────────
info "5단계: Homebrew tap 레포 확인"
if ! gh repo view "$TAP_REPO" >/dev/null 2>&1; then
  warn "$TAP_REPO 이 없음. 생성합니다..."
  read -p "Homebrew tap 레포를 Public으로 생성하시겠습니까? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    err "취소됨"
    exit 1
  fi
  gh repo create "$TAP_REPO" --public \
    --description "Homebrew tap for Cromaiping (cromaizing.com)" \
    --homepage "https://cromaizing.com/cromaiping"
  ok "Tap 레포 생성됨"
else
  ok "Tap 레포 이미 존재"
fi

# ─────────────────────────────────────────────
# 6. Formula 작성 + 푸시
# ─────────────────────────────────────────────
info "6단계: Formula 업데이트 + 푸시"
TAP_DIR=$(mktemp -d)
trap "rm -rf '$TAP_DIR'" EXIT

gh repo clone "$TAP_REPO" "$TAP_DIR" -- --depth 1 2>&1 | tail -3 || {
  # 빈 레포면 init
  git init "$TAP_DIR"
  cd "$TAP_DIR"
  git remote add origin "https://github.com/${TAP_REPO}.git"
  cd - >/dev/null
}

mkdir -p "$TAP_DIR/Formula"

# Formula 동적 생성 (실제 SHA256 + URL 적용)
cat > "$TAP_DIR/Formula/cromaiping.rb" <<FORMULA
class Cromaiping < Formula
  desc "AI 코딩 도구용 한국형 사운드 알림 시스템 (CESP v1.0 호환)"
  homepage "https://cromaizing.com/cromaiping"
  url "$TARBALL_URL"
  sha256 "$SHA256"
  version "$VERSION"
  license "MIT"

  depends_on "python@3.11" => :recommended

  def install
    libexec.install Dir["*"]

    (bin/"cromaiping").write <<~SH
      #!/bin/bash
      exec bash "#{libexec}/cromaiping.sh" "\$@"
    SH
    (bin/"cromaiping").chmod 0755
  end

  def caveats
    <<~EOS
      🎵 크로마이핑이 설치되었습니다.

      Claude Code 훅을 등록하려면 다음 명령어를 한 번만 실행해주세요:
        bash #{opt_libexec}/install.sh

      그 후 Claude Code를 재시작하시면 사운드 알림이 동작합니다.

      기본 명령어:
        cromaiping status         # 상태 확인
        cromaiping list           # 설치된 팩 목록
        cromaiping preview        # 사운드 미리듣기
        cromaiping packs list --registry
        cromaiping help

      홈페이지: https://cromaizing.com/cromaiping
    EOS
  end

  test do
    assert_match "크로마이핑", shell_output("#{bin}/cromaiping version")
  end
end
FORMULA

# Tap README도 만들기
cat > "$TAP_DIR/README.md" <<README
# Cromaizing Homebrew Tap

크로마이핑 [Homebrew](https://brew.sh) tap.

## 설치

\`\`\`bash
brew install cromaizing/tap/cromaiping
\`\`\`

## 사용법

\`\`\`bash
cromaiping status
cromaiping help
\`\`\`

## 링크

- [크로마이핑 홈페이지](https://cromaizing.com/cromaiping)
- [GitHub 레포](https://github.com/cromaizing/cromaiping)
README

cd "$TAP_DIR"
git add -A
if git diff --cached --quiet; then
  ok "Formula 변경사항 없음"
else
  git -c user.name="$(git config --global user.name)" \
      -c user.email="$(git config --global user.email)" \
      commit -m "feat: cromaiping v${VERSION} Formula"
  if ! git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -q main; then
    git branch -M main
  fi
  git push -u origin main
  ok "Formula 푸시 완료"
fi
cd - >/dev/null

# ─────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────
echo ""
ok "🎉 릴리즈 출판 완료!"
echo ""
cat <<DONE
  📌 사용자가 이제 다음과 같이 설치할 수 있습니다:

  🍺 Homebrew (가장 깔끔):
     brew install cromaizing/tap/cromaiping

  ⚡ Curl one-liner:
     curl -fsSL https://github.com/cromaizing/cromaiping/releases/latest/download/install.sh | bash

  📦 Git 클론:
     gh repo clone cromaizing/cromaiping
     cd cromaiping && bash install.sh

  🔗 링크:
     • Release: $RELEASE_URL
     • Tap:     https://github.com/$TAP_REPO
     • Formula: https://github.com/$TAP_REPO/blob/main/Formula/cromaiping.rb

  📋 다음 버전 릴리즈할 때:
     bash scripts/publish-release.sh 0.2.0
DONE
echo ""
