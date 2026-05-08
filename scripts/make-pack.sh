#!/bin/bash
# 크로마이핑 팩 자동 생성기
# 사용법: bash scripts/make-pack.sh <pack-info.txt> [출력경로]
#
# 입력 파일 형식:
#   # pack-info
#   name: yuna_friendly
#   display_name: 유나 친절이
#   description: 친절한 AI 비서
#   voice: Yuna                    # macOS say 음성 (선택)
#   audio_dir: ./recorded/         # 직접 녹음 파일 경로 (voice 대신)
#   license: MIT
#   author: 우수에프앤씨
#
#   [session.start]
#   시작할게요
#   준비됐어요
#
#   [task.complete]
#   끝났어요
#   완료입니다
set -euo pipefail

GREEN="\033[32m"; BLUE="\033[34m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${BLUE}ℹ${RESET}  $*"; }
ok()    { echo -e "${GREEN}✓${RESET}  $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET}  $*"; }
err()   { echo -e "${RED}✗${RESET}  $*" >&2; }

INPUT_FILE="${1:-}"
[ -z "$INPUT_FILE" ] && { err "사용법: bash make-pack.sh <input.txt> [출력경로]"; exit 1; }
[ ! -f "$INPUT_FILE" ] && { err "파일을 찾을 수 없음: $INPUT_FILE"; exit 1; }

OUTPUT_BASE="${2:-${HOME}/.claude/hooks/cromaiping/packs}"

# 입력 파일 파싱 (Python으로)
export INPUT_PATH="$INPUT_FILE"
PARSED=$(python3 <<'PYEOF'
import os, re, json, sys

path = os.environ['INPUT_PATH']
content = open(path).read()

# 메타 추출 (key: value)
meta = {}
phrases = {}
current_section = None

for line in content.split('\n'):
    line = line.rstrip()
    if not line or line.startswith('#'):
        continue
    if line.startswith('[') and line.endswith(']'):
        current_section = line[1:-1].strip()
        phrases[current_section] = []
        continue
    if current_section is None:
        # 메타 영역
        if ':' in line:
            k, v = line.split(':', 1)
            meta[k.strip()] = v.strip()
    else:
        # 문구 영역
        line = line.strip()
        if line:
            phrases[current_section].append(line)

result = {'meta': meta, 'phrases': phrases}
print(json.dumps(result, ensure_ascii=False))
PYEOF
)

# 메타데이터 추출
NAME=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('name',''))")
DISPLAY_NAME=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('display_name', ''))")
DESCRIPTION=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('description',''))")
VOICE=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('voice',''))")
AUDIO_DIR=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('audio_dir',''))")
LICENSE=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('license','MIT'))")
AUTHOR=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('author','Cromaiping'))")
LANGUAGE=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('language','ko'))")
VERSION=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['meta'].get('version','1.0.0'))")

# 검증
[ -z "$NAME" ] && { err "name 필드가 비어있음"; exit 1; }
[ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="$NAME"
echo "$NAME" | grep -qE '^[a-z0-9][a-z0-9_-]*$' || { err "name은 소문자 알파벳/숫자/하이픈/언더스코어만 가능: $NAME"; exit 1; }

if [ -z "$VOICE" ] && [ -z "$AUDIO_DIR" ]; then
  err "voice (TTS 음성명) 또는 audio_dir (녹음 파일 경로) 중 하나는 필수"
  exit 1
fi

PACK_DIR="$OUTPUT_BASE/$NAME"
SOUND_DIR="$PACK_DIR/sounds"
MANIFEST="$PACK_DIR/openpeon.json"

cat <<BANNER
╔══════════════════════════════════════════╗
║  크로마이핑 팩 자동 생성                 ║
╚══════════════════════════════════════════╝

  팩 이름:    $NAME
  표시명:     $DISPLAY_NAME
  설명:       $DESCRIPTION
  음성:       ${VOICE:-(녹음 파일 사용)}
  출력 경로:  $PACK_DIR
BANNER
echo ""

# 기존 팩 백업
if [ -d "$PACK_DIR" ]; then
  warn "기존 팩 발견 — ${PACK_DIR}.bak 으로 백업"
  rm -rf "${PACK_DIR}.bak"
  mv "$PACK_DIR" "${PACK_DIR}.bak"
fi

mkdir -p "$SOUND_DIR"

# 카테고리별 사운드 생성
SOUND_TOTAL=0
CATEGORIES_JSON=""

for CATEGORY in session.start task.acknowledge task.complete task.error input.required resource.limit user.spam session.end task.progress; do
  CAT_PHRASES=$(echo "$PARSED" | CATEGORY="$CATEGORY" python3 -c "
import json, sys, os
data = json.load(sys.stdin)
phrases = data['phrases'].get(os.environ['CATEGORY'], [])
print('\n'.join(phrases))
")

  [ -z "$CAT_PHRASES" ] && continue

  info "카테고리: $CATEGORY"
  CAT_SAFE=$(echo "$CATEGORY" | tr '.' '_')
  IDX=1
  CAT_SOUNDS_JSON=""

  while IFS= read -r PHRASE; do
    [ -z "$PHRASE" ] && continue

    FILENAME="${CAT_SAFE}_$(printf '%02d' $IDX).wav"
    FILEPATH="$SOUND_DIR/$FILENAME"

    if [ -n "$VOICE" ]; then
      # macOS say로 생성
      if command -v say >/dev/null 2>&1; then
        TMP_AIFF="$(mktemp -t pack).aiff"
        say -v "$VOICE" -o "$TMP_AIFF" "$PHRASE" 2>/dev/null
        afconvert "$TMP_AIFF" "$FILEPATH" -d LEI16 -f WAVE 2>/dev/null
        rm -f "$TMP_AIFF"
        echo "    [$IDX] $PHRASE → $FILENAME"
      else
        warn "    say 명령어 없음 (macOS 필요)"
        continue
      fi
    elif [ -n "$AUDIO_DIR" ]; then
      # 녹음 파일에서 가져오기 (file_$IDX 형식 가정)
      SRC=$(find "$AUDIO_DIR" -type f \( -name "${CAT_SAFE}_${IDX}*" -o -name "${CATEGORY}_${IDX}*" \) | head -1)
      if [ -n "$SRC" ] && [ -f "$SRC" ]; then
        cp "$SRC" "$FILEPATH"
        echo "    [$IDX] $PHRASE ← $(basename "$SRC")"
      else
        warn "    [$IDX] 파일 없음: ${CAT_SAFE}_${IDX}.* in $AUDIO_DIR"
        IDX=$((IDX + 1))
        continue
      fi
    fi

    # JSON 항목 추가
    if [ -n "$CAT_SOUNDS_JSON" ]; then
      CAT_SOUNDS_JSON="${CAT_SOUNDS_JSON},"
    fi
    LABEL_ESCAPED=$(printf '%s' "$PHRASE" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().rstrip(), ensure_ascii=False))")
    CAT_SOUNDS_JSON="${CAT_SOUNDS_JSON}{\"file\":\"sounds/$FILENAME\",\"label\":${LABEL_ESCAPED}}"

    IDX=$((IDX + 1))
    SOUND_TOTAL=$((SOUND_TOTAL + 1))
  done <<< "$CAT_PHRASES"

  # 카테고리 JSON 추가
  if [ -n "$CAT_SOUNDS_JSON" ]; then
    if [ -n "$CATEGORIES_JSON" ]; then
      CATEGORIES_JSON="${CATEGORIES_JSON},"
    fi
    CATEGORIES_JSON="${CATEGORIES_JSON}\"$CATEGORY\":{\"sounds\":[$CAT_SOUNDS_JSON]}"
  fi
done

# openpeon.json 작성
ok "매니페스트 생성 중..."
export PACK_NAME="$NAME"
export PACK_DISPLAY="$DISPLAY_NAME"
export PACK_DESC="$DESCRIPTION"
export PACK_VERSION="$VERSION"
export PACK_LICENSE="$LICENSE"
export PACK_AUTHOR="$AUTHOR"
export PACK_LANG="$LANGUAGE"
export PACK_CATEGORIES="$CATEGORIES_JSON"

python3 <<'PYEOF' > "$MANIFEST"
import os, json
manifest = {
    "cesp_version": "1.0",
    "name": os.environ['PACK_NAME'],
    "display_name": os.environ['PACK_DISPLAY'],
    "version": os.environ['PACK_VERSION'],
    "description": os.environ['PACK_DESC'],
    "author": {"name": os.environ['PACK_AUTHOR']},
    "license": os.environ['PACK_LICENSE'],
    "language": os.environ['PACK_LANG'],
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

# 검증
ok "매니페스트 검증..."
python3 -c "
import json
m = json.load(open('$MANIFEST'))
assert m['cesp_version'] == '1.0'
assert m['name']
assert m['categories']
print('  ✓ CESP v1.0 호환')
"

# 결과
TOTAL_SIZE=$(du -sk "$PACK_DIR" | cut -f1)
echo ""
ok "✨ 팩 생성 완료!"
echo ""
echo "  📁 경로:    $PACK_DIR"
echo "  🎵 사운드:  $SOUND_TOTAL 개"
echo "  💾 크기:    $TOTAL_SIZE KB"
echo "  📋 매니페스트: $MANIFEST"
echo ""
echo "  미리듣기 → cromaiping packs use $NAME"
echo "             cromaiping preview"
echo ""

# 백업 정리
rm -rf "${PACK_DIR}.bak" 2>/dev/null || true
