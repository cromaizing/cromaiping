#!/bin/bash
# 크로마이핑 배포 tarball 빌드 스크립트
# cromaizing.com에 업로드할 cromaiping-latest.tar.gz 생성
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION" | tr -d '[:space:]')
DIST_DIR="$PROJECT_ROOT/dist"
mkdir -p "$DIST_DIR"

OUTPUT="$DIST_DIR/cromaiping-${VERSION}.tar.gz"
LATEST="$DIST_DIR/cromaiping-latest.tar.gz"

# 부모 디렉토리에서 cromaiping/ 자체를 묶음 (구조 유지)
PARENT="$(dirname "$PROJECT_ROOT")"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"

cd "$PARENT"

# 임시로 dist를 외부로 옮겼다가 (tar 안에 포함 방지) 다시 복원
TMP_OUT="$(mktemp -d)/cromaiping-build.tar.gz"

tar --exclude="${PROJECT_NAME}/.git" \
    --exclude="${PROJECT_NAME}/dist" \
    --exclude="${PROJECT_NAME}/.state.json" \
    --exclude="${PROJECT_NAME}/.sound.pid" \
    --exclude="${PROJECT_NAME}/.last_update_check" \
    --exclude='*.log' \
    --exclude="${PROJECT_NAME}/logs" \
    --exclude='.DS_Store' \
    --exclude="${PROJECT_NAME}/packs/cromaiping_default/sounds/*.wav" \
    --exclude="${PROJECT_NAME}/packs/cromaiping_default/sounds/*.aiff" \
    -czf "$TMP_OUT" \
    "${PROJECT_NAME}"

# 디렉토리 이름이 "cromaiping"이 아니면 내부에서 rename
if [ "$PROJECT_NAME" != "cromaiping" ]; then
  STAGING="$(mktemp -d)"
  tar -xzf "$TMP_OUT" -C "$STAGING"
  mv "$STAGING/$PROJECT_NAME" "$STAGING/cromaiping"
  (cd "$STAGING" && tar -czf "$OUTPUT" cromaiping)
  rm -rf "$STAGING"
else
  mv "$TMP_OUT" "$OUTPUT"
fi
rm -f "$TMP_OUT"

# latest 심볼릭 링크 (또는 복사)
cp "$OUTPUT" "$LATEST"

SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "✓ Built: $OUTPUT ($SIZE)"
echo "✓ Latest: $LATEST"
echo ""
echo "📦 업로드할 파일:"
echo "   - $LATEST       → https://cromaizing.com/cromaiping/cromaiping-latest.tar.gz"
echo "   - $OUTPUT       → https://cromaizing.com/cromaiping/cromaiping-${VERSION}.tar.gz"
echo "   - install.sh    → https://cromaizing.com/cromaiping/install.sh"
echo ""
echo "✨ 설치 one-liner:"
echo "   curl -fsSL https://cromaizing.com/cromaiping/install.sh | bash"
