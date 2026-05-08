#!/bin/bash
# 크로마이핑 슬래시 명령어 인터셉터
# UserPromptSubmit 훅에 등록되어 사용자 입력을 LLM에 도달하기 전에 가로챔
#
# 지원 명령어:
#   /cromaiping-use <팩>      → 이번 세션 팩 변경
#   /cromaiping-toggle        → 음소거 토글
#   /cromaiping-volume <0-100>→ 볼륨 변경
#   /cromaiping-status        → 현재 상태
#   /크로마이핑-팩 <팩>       → 한국어 별칭
set -euo pipefail

# CONFIG_DIR 결정 (설치 위치 우선, 없으면 스크립트 부모 디렉토리)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping"
if [ -d "$DEFAULT_CONFIG_DIR" ]; then
  CONFIG_DIR="$DEFAULT_CONFIG_DIR"
else
  CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
fi
CONFIG_FILE="$CONFIG_DIR/config.json"
STATE_FILE="$CONFIG_DIR/.state.json"
LOG_FILE="$CONFIG_DIR/cmd-intercept.log"

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

INPUT=$(cat)
log "invoked stdin_len=${#INPUT}"

# Python으로 명령어 파싱 (BSD sed/awk보다 안정적)
export INTERCEPT_INPUT="$INPUT"
PARSED=$(python3 <<'PYEOF'
import json, os, re, sys

raw = os.environ.get('INTERCEPT_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

prompt = data.get('prompt', '').strip()
session = data.get('session_id') or data.get('conversation_id') or 'default'

# /cromaiping-XXX 또는 /크로마이핑-XXX 패턴 매치
m = re.match(r'^\s*/(cromaiping|크로마이핑)-([a-z가-힣]+)\s*(.*)$', prompt, re.IGNORECASE)
if not m:
    sys.exit(0)  # 우리 명령어 아님 → passthrough

cmd = m.group(2).lower()
arg = m.group(3).strip()
print(f"CMD={cmd}")
print(f"ARG={arg}")
print(f"SESSION={session}")
PYEOF
)

# 매치 안 되면 passthrough (출력 없음 → LLM에 정상 전달됨)
[ -z "$PARSED" ] && { log "passthrough"; exit 0; }

# 결과 파싱
CMD=""; ARG=""; SESSION_ID="default"
while IFS='=' read -r key val; do
  case "$key" in
    CMD) CMD="$val" ;;
    ARG) ARG="$val" ;;
    SESSION) SESSION_ID="$val" ;;
  esac
done <<< "$PARSED"

log "cmd=$CMD arg=$ARG"

# 응답 함수 (LLM 호출 차단 + 사용자 메시지)
respond() {
  local message="$1"
  export RESP_MSG="$message"
  python3 -c "
import json, os
print(json.dumps({'continue': False, 'user_message': os.environ.get('RESP_MSG', '')}, ensure_ascii=False))
"
  exit 0
}

# 명령어 디스패치
case "$CMD" in
  use|pack|팩)
    [ -z "$ARG" ] && respond "❌ 팩 이름을 입력해주세요. 예: /cromaiping-use cromaiping_default"
    PACK_DIR="$CONFIG_DIR/packs/$ARG"
    [ -d "$PACK_DIR" ] || respond "❌ 팩을 찾을 수 없습니다: $ARG"
    export PACK_NAME="$ARG"
    python3 <<'PYEOF'
import json, os, time
sf = os.environ.get('STATE_FILE_PATH') or '$STATE_FILE'
sid = os.environ.get('SESSION_ID', 'default')
pack = os.environ.get('PACK_NAME', '')
state = {}
if os.path.exists(sf):
    try: state = json.load(open(sf))
    except: pass
state.setdefault('session_packs', {})[sid] = {'pack': pack, 'last_used': time.time()}
json.dump(state, open(sf, 'w'), ensure_ascii=False, indent=2)
PYEOF
    respond "🎵 이번 세션 팩이 '$ARG'(으)로 변경되었습니다."
    ;;

  toggle)
    NEW_STATE=$(CONFIG_FILE_PATH="$CONFIG_FILE" python3 <<'PYEOF'
import json, os
cfg_path = os.environ['CONFIG_FILE_PATH']
cfg = json.load(open(cfg_path))
cfg['enabled'] = not cfg.get('enabled', True)
json.dump(cfg, open(cfg_path,'w'), ensure_ascii=False, indent=2)
print('on' if cfg['enabled'] else 'off')
PYEOF
)
    if [ "$NEW_STATE" = "on" ]; then
      respond "🔊 크로마이핑 활성화됨"
    else
      respond "🔇 크로마이핑 음소거됨"
    fi
    ;;

  mute|음소거)
    CONFIG_FILE_PATH="$CONFIG_FILE" python3 <<'PYEOF'
import json, os
p = os.environ['CONFIG_FILE_PATH']
cfg = json.load(open(p))
cfg['enabled'] = False
json.dump(cfg, open(p,'w'), ensure_ascii=False, indent=2)
PYEOF
    respond "🔇 크로마이핑 음소거됨"
    ;;

  unmute|활성)
    CONFIG_FILE_PATH="$CONFIG_FILE" python3 <<'PYEOF'
import json, os
p = os.environ['CONFIG_FILE_PATH']
cfg = json.load(open(p))
cfg['enabled'] = True
json.dump(cfg, open(p,'w'), ensure_ascii=False, indent=2)
PYEOF
    respond "🔊 크로마이핑 활성화됨"
    ;;

  volume|볼륨)
    if [ -z "$ARG" ]; then
      VOL=$(CONFIG_FILE_PATH="$CONFIG_FILE" python3 -c "import json,os; print(int(json.load(open(os.environ['CONFIG_FILE_PATH']))['volume']*100))")
      respond "🔊 현재 볼륨: ${VOL}%"
    fi
    NEW_VOL=$(VOL_ARG="$ARG" CONFIG_FILE_PATH="$CONFIG_FILE" python3 <<'PYEOF'
import json, os, sys
try:
    v = float(os.environ['VOL_ARG'])
    if v > 1: v = v / 100
    v = max(0.0, min(1.0, v))
    p = os.environ['CONFIG_FILE_PATH']
    cfg = json.load(open(p))
    cfg['volume'] = v
    json.dump(cfg, open(p,'w'), ensure_ascii=False, indent=2)
    print(int(v*100))
except Exception:
    print('ERROR')
PYEOF
)
    [ "$NEW_VOL" = "ERROR" ] && respond "❌ 볼륨 값이 올바르지 않습니다 (0-100)"
    respond "🔊 볼륨이 ${NEW_VOL}%로 설정되었습니다."
    ;;

  status|상태)
    INFO=$(CONFIG_FILE_PATH="$CONFIG_FILE" python3 <<'PYEOF'
import json, os
cfg = json.load(open(os.environ['CONFIG_FILE_PATH']))
state = '활성' if cfg.get('enabled', True) else '음소거'
pack = cfg.get('default_pack', '-')
vol = int(cfg.get('volume', 0.5)*100)
notif = '켜짐' if cfg.get('desktop_notifications', True) else '꺼짐'
print(f'상태: {state} / 기본 팩: {pack} / 볼륨: {vol}% / 알림: {notif}')
PYEOF
)
    respond "📊 $INFO"
    ;;

  list|목록|팩목록)
    LIST=$(CONFIG_DIR_PATH="$CONFIG_DIR" python3 <<'PYEOF'
import json, os
pack_dir = os.path.join(os.environ['CONFIG_DIR_PATH'], 'packs')
items = []
if os.path.isdir(pack_dir):
    for name in sorted(os.listdir(pack_dir)):
        manifest = os.path.join(pack_dir, name, 'openpeon.json')
        if os.path.isfile(manifest):
            try:
                m = json.load(open(manifest))
                items.append(f'  • {name} — {m.get("display_name", name)}')
            except:
                items.append(f'  • {name}')
print('\n'.join(items) if items else '  (설치된 팩 없음)')
PYEOF
)
    respond "📦 설치된 팩:
$LIST

💡 더 많은 팩: 터미널에서 cromaiping packs list --registry"
    ;;

  install|설치)
    [ -z "$ARG" ] && respond "❌ 팩 이름을 입력해주세요. 예: /cromaiping-install peon"
    # 비동기 실행 권장: 슬래시 핸들러는 5초 타임아웃이라 다운로드는 외부에서
    respond "🌐 '$ARG' 다운로드를 시작합니다.

터미널에서 다음을 실행해주세요:
\`cromaiping packs install $ARG\`

(다운로드는 시간이 걸리는 작업이라 슬래시 명령어 대신 터미널에서 진행해주세요)"
    ;;

  search|검색)
    [ -z "$ARG" ] && respond "❌ 검색 키워드를 입력해주세요. 예: /cromaiping-search 한국어"
    respond "🔍 검색 결과를 보려면 터미널에서:
\`cromaiping packs search $ARG\`"
    ;;

  help|도움말)
    respond "🎵 크로마이핑 명령어:
/cromaiping-use <팩>       이번 세션 팩 변경
/cromaiping-toggle         음소거 토글
/cromaiping-volume <0-100> 볼륨 변경
/cromaiping-status         현재 상태
/cromaiping-list           설치된 팩 목록
/cromaiping-help           이 도움말

홈페이지: https://cromaizing.com/cromaiping"
    ;;

  *)
    log "unknown_cmd: $CMD"
    exit 0
    ;;
esac
