#!/bin/bash
# 크로마이핑 음원 파일 → 팩 임포트 스크립트
# 카테고리별로 이미 녹음/생성된 음원 파일이 있을 때 사용
#
# 사용법:
#   bash scripts/import-pack.sh <팩이름> <음원폴더> [표시명]
#
# 예시:
#   bash scripts/import-pack.sh karina ./Karina "카리나"
#
# 음원 폴더 안의 파일명 규칙:
#   <category>.mp3                 (1개씩, 가장 단순)
#   <category>_<num>.mp3           (다중)
#   <category>.wav / .ogg          (다른 포맷)
#
# 카테고리: session.start, task.acknowledge, task.complete, task.error,
#           input.required, resource.limit, user.spam, session.end, task.progress
set -euo pipefail

GREEN="\033[32m"; BLUE="\033[34m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${BLUE}ℹ${RESET}  $*"; }
ok()    { echo -e "${GREEN}✓${RESET}  $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET}  $*"; }
err()   { echo -e "${RED}✗${RESET}  $*" >&2; }

PACK_NAME="${1:-}"
SRC_DIR="${2:-}"
DISPLAY_NAME="${3:-$PACK_NAME}"

[ -z "$PACK_NAME" ] && { err "사용법: bash import-pack.sh <팩이름> <음원폴더> [표시명]"; exit 1; }
[ -z "$SRC_DIR" ] && { err "음원 폴더 경로 필요"; exit 1; }
[ ! -d "$SRC_DIR" ] && { err "폴더 없음: $SRC_DIR"; exit 1; }

echo "$PACK_NAME" | grep -qE '^[a-z0-9][a-z0-9_-]*$' || { err "팩 이름은 소문자/숫자/하이픈/언더스코어만: $PACK_NAME"; exit 1; }

INSTALL_DIR="${HOME}/.claude/hooks/cromaiping/packs/$PACK_NAME"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packs/$PACK_NAME"

cat <<BANNER
╔══════════════════════════════════════════╗
║  크로마이핑 팩 임포트                    ║
╚══════════════════════════════════════════╝

  팩 이름:    $PACK_NAME
  표시명:     $DISPLAY_NAME
  음원:       $SRC_DIR
  설치 위치:  $INSTALL_DIR
BANNER
echo ""

# 카테고리별 라벨 (기본값)
get_label() {
  case "$1" in
    session.start) echo "세션 시작" ;;
    task.acknowledge) echo "작업 시작" ;;
    task.complete) echo "작업 완료" ;;
    task.error) echo "에러 발생" ;;
    input.required) echo "입력 필요" ;;
    resource.limit) echo "리소스 한계" ;;
    user.spam) echo "빠른 입력 감지" ;;
    session.end) echo "세션 종료" ;;
    task.progress) echo "작업 진행 중" ;;
    *) echo "사운드" ;;
  esac
}

# 매직바이트 검증 (4 hex chars)
verify_audio() {
  local file="$1"
  local magic=$(head -c 4 "$file" | xxd -p 2>/dev/null)
  case "$magic" in
    52494646*) echo "wav" ;;
    49443*|fffb*|fff3*|fff2*) echo "mp3" ;;
    4f676753*) echo "ogg" ;;
    *) echo "" ;;
  esac
}

# 디렉토리 초기화
for D in "$INSTALL_DIR" "$PROJECT_DIR"; do
  rm -rf "$D"
  mkdir -p "$D/sounds"
done

# 카테고리 매핑 + 복사
CATEGORIES_JSON=""
TOTAL=0
SIZE_TOTAL=0

for CAT in session.start task.acknowledge task.complete task.error input.required resource.limit user.spam session.end task.progress; do
  CAT_SAFE=$(echo "$CAT" | tr '.' '_')
  IDX=1
  CAT_SOUNDS=""

  # 패턴 매칭: <cat>.<ext>, <cat>_<n>.<ext>
  for f in "$SRC_DIR"/"$CAT".mp3 "$SRC_DIR"/"$CAT".wav "$SRC_DIR"/"$CAT".ogg \
           "$SRC_DIR"/"$CAT"_*.mp3 "$SRC_DIR"/"$CAT"_*.wav "$SRC_DIR"/"$CAT"_*.ogg \
           "$SRC_DIR"/"$CAT_SAFE".mp3 "$SRC_DIR"/"$CAT_SAFE".wav "$SRC_DIR"/"$CAT_SAFE".ogg \
           "$SRC_DIR"/"$CAT_SAFE"_*.mp3 "$SRC_DIR"/"$CAT_SAFE"_*.wav "$SRC_DIR"/"$CAT_SAFE"_*.ogg; do
    [ -f "$f" ] || continue

    # 매직바이트 검증
    fmt=$(verify_audio "$f")
    if [ -z "$fmt" ]; then
      warn "    매직바이트 불일치: $(basename "$f") - 스킵"
      continue
    fi

    EXT=$(basename "$f" | awk -F. '{print $NF}')
    DST_NAME="${CAT_SAFE}_$(printf '%02d' $IDX).${EXT}"

    for D in "$INSTALL_DIR" "$PROJECT_DIR"; do
      cp "$f" "$D/sounds/$DST_NAME"
    done

    LABEL=$(get_label "$CAT")
    if [ -n "$CAT_SOUNDS" ]; then
      CAT_SOUNDS="${CAT_SOUNDS},"
    fi
    CAT_SOUNDS="${CAT_SOUNDS}{\"file\":\"sounds/$DST_NAME\",\"label\":\"$LABEL\"}"

    SIZE=$(du -k "$f" | cut -f1)
    SIZE_TOTAL=$((SIZE_TOTAL + SIZE))
    TOTAL=$((TOTAL + 1))
    IDX=$((IDX + 1))
    echo "  ✓ $CAT → sounds/$DST_NAME ($fmt, ${SIZE}KB)"
  done

  if [ -n "$CAT_SOUNDS" ]; then
    if [ -n "$CATEGORIES_JSON" ]; then
      CATEGORIES_JSON="${CATEGORIES_JSON},"
    fi
    CATEGORIES_JSON="${CATEGORIES_JSON}\"$CAT\":{\"sounds\":[$CAT_SOUNDS]}"
  fi
done

if [ "$TOTAL" -eq 0 ]; then
  err "매칭되는 음원 파일이 없습니다."
  rm -rf "$INSTALL_DIR" "$PROJECT_DIR"
  exit 1
fi

# 사이즈 제한 (50MB)
if [ "$SIZE_TOTAL" -gt 51200 ]; then
  err "팩 크기 초과: ${SIZE_TOTAL}KB > 50MB"
  rm -rf "$INSTALL_DIR" "$PROJECT_DIR"
  exit 1
fi

# 매니페스트 생성
export PACK_NAME PACK_DISPLAY="$DISPLAY_NAME" PACK_CATEGORIES="$CATEGORIES_JSON"
for D in "$INSTALL_DIR" "$PROJECT_DIR"; do
  python3 <<PYEOF > "$D/openpeon.json"
import os, json
manifest = {
    "cesp_version": "1.0",
    "name": os.environ['PACK_NAME'],
    "display_name": os.environ['PACK_DISPLAY'],
    "version": "1.0.0",
    "description": "$DISPLAY_NAME 사운드 팩",
    "author": {"name": "Cromaizing"},
    "license": "CC-BY-NC-4.0",
    "language": "ko",
    "homepage": "https://cromaizing.com/cromaiping",
    "categories": json.loads('{' + os.environ['PACK_CATEGORIES'] + '}'),
    "category_aliases": {
        "greeting": "session.start",
        "complete": "task.complete",
        "error": "task.error",
        "permission": "input.required",
        "resource_limit": "resource.limit",
        "annoyed": "user.spam"
    }
}
print(json.dumps(manifest, ensure_ascii=False, indent=2))
PYEOF
done

ok "매니페스트 작성 완료"
echo ""
ok "✨ 임포트 완료!"
echo ""
echo "  📁 설치:    $INSTALL_DIR"
echo "  📁 프로젝트: $PROJECT_DIR"
echo "  🎵 사운드:  $TOTAL 개"
echo "  💾 크기:    $((SIZE_TOTAL))KB"
echo ""
echo "  활성화 → cromaiping packs use $PACK_NAME"
echo "  미리듣기 → cromaiping preview"
echo ""
