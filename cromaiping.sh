#!/bin/bash
# 크로마이핑 (Cromaiping) — AI 코딩 도구용 한국형 사운드 알림
# CESP v1.0 호환 / peon-ping 아키텍처 기반
# 메인 훅 핸들러: stdin으로 받은 이벤트 JSON을 파싱해 카테고리 매핑 후 사운드 재생
set -uo pipefail

VERSION="0.1.0"

# ─────────────────────────────────────────────
# 경로 해석 (Homebrew/Nix/표준 설치 + symlink 모두 지원)
# ─────────────────────────────────────────────
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
CROMAIPING_DIR="${CROMAIPING_DIR:-$SCRIPT_DIR}"

# 설정/상태 파일은 사용자 홈에 (read-only 설치 대비)
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping"
[ -d "$CONFIG_DIR" ] || CONFIG_DIR="$CROMAIPING_DIR"
CONFIG_FILE="$CONFIG_DIR/config.json"
STATE_FILE="$CONFIG_DIR/.state.json"
LOG_FILE="$CONFIG_DIR/cromaiping.log"

# ─────────────────────────────────────────────
# 플랫폼 감지
# ─────────────────────────────────────────────
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then echo "wsl"
      elif [ -n "${SSH_CONNECTION:-}" ]; then echo "ssh"
      else echo "linux"; fi ;;
    MSYS_NT*|MINGW*) echo "msys2" ;;
    *) echo "unknown" ;;
  esac
}
PLATFORM="${CROMAIPING_PLATFORM:-$(detect_platform)}"

# ─────────────────────────────────────────────
# 로깅 (디버그 모드일 때만)
# ─────────────────────────────────────────────
log() {
  [ "${CROMAIPING_DEBUG:-0}" = "1" ] || return 0
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# 사운드 재생 (플랫폼별)
# ─────────────────────────────────────────────
play_sound() {
  local file="$1" vol="${2:-0.5}"
  [ -f "$file" ] || { log "play: file_not_found $file"; return 1; }

  case "$PLATFORM" in
    mac)
      # 우선순위: 자체 컴파일된 play 바이너리 → afplay
      if [ -x "$CROMAIPING_DIR/scripts/play" ]; then
        nohup "$CROMAIPING_DIR/scripts/play" -v "$vol" "$file" >/dev/null 2>&1 &
      else
        nohup afplay -v "$vol" "$file" >/dev/null 2>&1 &
      fi ;;
    linux|wsl)
      for player in pw-play paplay ffplay mpv play aplay; do
        if command -v "$player" >/dev/null 2>&1; then
          case "$player" in
            ffplay) nohup ffplay -nodisp -autoexit -volume $(printf '%.0f' "$(echo "$vol*100" | bc -l)") "$file" >/dev/null 2>&1 & ;;
            mpv) nohup mpv --no-video --volume="$(echo "$vol*100" | bc -l)" "$file" >/dev/null 2>&1 & ;;
            *) nohup "$player" "$file" >/dev/null 2>&1 & ;;
          esac
          break
        fi
      done ;;
    msys2)
      command -v powershell.exe >/dev/null 2>&1 && \
        powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '$file').PlaySync()" >/dev/null 2>&1 & ;;
  esac
  log "play: $file vol=$vol"
}

# ─────────────────────────────────────────────
# 데스크톱 알림 (플랫폼별)
# ─────────────────────────────────────────────
notify() {
  local msg="$1" title="${2:-크로마이핑}"
  case "$PLATFORM" in
    mac)
      osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null & ;;
    linux)
      command -v notify-send >/dev/null 2>&1 && notify-send "$title" "$msg" 2>/dev/null & ;;
  esac
}

# ─────────────────────────────────────────────
# CLI 모드 (stdin이 TTY이거나 인자가 있을 때)
# ─────────────────────────────────────────────
if [ -t 0 ] || [ $# -gt 0 ]; then
  case "${1:-help}" in
    version|--version|-v) echo "크로마이핑 v$VERSION"; exit 0 ;;
    status)
      python3 -c "
import json, os
cfg = json.load(open('$CONFIG_FILE'))
print(f'크로마이핑: {\"활성\" if cfg.get(\"enabled\", True) else \"음소거\"}')
print(f'기본 팩: {cfg.get(\"default_pack\", \"-\")}')
print(f'볼륨: {int(cfg.get(\"volume\", 0.5)*100)}%')
print(f'데스크톱 알림: {\"on\" if cfg.get(\"desktop_notifications\", True) else \"off\"}')
"
      exit 0 ;;
    pause|mute)
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['enabled'] = False
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('크로마이핑: 음소거됨')
"
      exit 0 ;;
    resume|unmute)
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['enabled'] = True
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('크로마이핑: 활성화됨')
"
      exit 0 ;;
    toggle)
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['enabled'] = not cfg.get('enabled', True)
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('크로마이핑: ' + ('활성화됨' if cfg['enabled'] else '음소거됨'))
"
      exit 0 ;;
    volume)
      shift
      if [ -n "${1:-}" ]; then
        python3 -c "
import json, sys
v = float(sys.argv[1])
v = max(0.0, min(1.0, v if v <= 1 else v/100))
cfg = json.load(open('$CONFIG_FILE'))
cfg['volume'] = v
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print(f'볼륨: {int(v*100)}%')
" "$1"
      else
        python3 -c "import json; print(f'볼륨: {int(json.load(open(\"$CONFIG_FILE\"))[\"volume\"]*100)}%')"
      fi
      exit 0 ;;
    use)
      shift
      [ -z "${1:-}" ] && { echo "사용법: cromaiping use <팩이름>"; exit 1; }
      pack_dir="$CROMAIPING_DIR/packs/$1"
      [ -d "$pack_dir" ] || { echo "팩을 찾을 수 없음: $1"; exit 1; }
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['default_pack'] = '$1'
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('팩이 변경됨: $1')
"
      exit 0 ;;
    list|packs)
      echo "설치된 팩:"
      for p in "$CROMAIPING_DIR/packs/"*/; do
        name=$(basename "$p")
        manifest="$p/openpeon.json"
        if [ -f "$manifest" ]; then
          display=$(python3 -c "import json; print(json.load(open('$manifest')).get('display_name', '$name'))" 2>/dev/null)
          echo "  $name — $display"
        fi
      done
      exit 0 ;;
    preview)
      shift
      cat="${1:-session.start}"
      pack=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['default_pack'])")
      manifest="$CROMAIPING_DIR/packs/$pack/openpeon.json"
      [ -f "$manifest" ] || { echo "매니페스트 없음: $manifest"; exit 1; }
      file=$(python3 -c "
import json, random
m = json.load(open('$manifest'))
sounds = m.get('categories', {}).get('$cat', {}).get('sounds', [])
if sounds:
    print('$CROMAIPING_DIR/packs/$pack/' + random.choice(sounds)['file'])
")
      [ -n "$file" ] && [ -f "$file" ] && play_sound "$file" "0.5" && echo "재생: $cat" || echo "사운드 없음: $cat"
      exit 0 ;;
    help|--help|-h|*)
      cat <<EOF
크로마이핑 v$VERSION — AI 코딩 도구용 한국형 사운드 알림

사용법: cromaiping <명령어> [인자]

명령어:
  status                현재 상태 확인
  toggle                음소거 토글
  pause / mute          음소거
  resume / unmute       활성화
  volume [0-100]        볼륨 조회/설정
  use <팩이름>          기본 팩 변경
  list                  설치된 팩 목록
  preview [카테고리]    카테고리 사운드 미리듣기
  version               버전 정보
  help                  이 도움말

설정 파일: $CONFIG_FILE
홈페이지: https://cromaizing.com/cromaiping
EOF
      exit 0 ;;
  esac
fi

# ─────────────────────────────────────────────
# 훅 모드: stdin으로 JSON 이벤트 수신
# ─────────────────────────────────────────────
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Python으로 이벤트 처리 (bash로 JSON 다루기 어려움)
RESULT=$(python3 <<PYEOF
import json, os, sys, random, time

CONFIG_FILE = "$CONFIG_FILE"
STATE_FILE = "$STATE_FILE"
CROMAIPING_DIR = "$CROMAIPING_DIR"

# 이벤트 파싱
try:
    event_data = json.loads(r'''$INPUT''')
except Exception as e:
    sys.exit(0)

# Cursor lowercaseEvent → PascalCase 변환
CURSOR_MAP = {
    'sessionStart': 'SessionStart', 'sessionEnd': 'SessionEnd',
    'beforeSubmitPrompt': 'UserPromptSubmit', 'stop': 'Stop',
    'preToolUse': 'UserPromptSubmit', 'postToolUse': 'Stop',
}
raw_event = event_data.get('hook_event_name', '')
event = CURSOR_MAP.get(raw_event, raw_event)

session_id = event_data.get('session_id') or event_data.get('conversation_id') or 'default'

# 설정 로드
try:
    cfg = json.load(open(CONFIG_FILE))
except Exception:
    cfg = {}

if not cfg.get('enabled', True):
    sys.exit(0)

# 카테고리 토글 확인
cats_enabled = cfg.get('categories', {})

# 상태 로드
try:
    state = json.load(open(STATE_FILE))
except Exception:
    state = {}

# 이벤트 → 카테고리 매핑
EVENT_MAP = {
    'SessionStart': 'session.start',
    'UserPromptSubmit': 'task.acknowledge',
    'Stop': 'task.complete',
    'SubagentStop': 'task.complete',
    'PermissionRequest': 'input.required',
    'PostToolUseFailure': 'task.error',
    'PreCompact': 'resource.limit',
}
category = EVENT_MAP.get(event)

# 특수 처리: SessionStart의 source=compact는 무시
if event == 'SessionStart' and event_data.get('source') == 'compact':
    sys.exit(0)

# 특수 처리: UserPromptSubmit 빠른 입력 → user.spam 감지
if event == 'UserPromptSubmit' and cats_enabled.get('user.spam', True):
    threshold = cfg.get('annoyed_threshold', 3)
    window = cfg.get('annoyed_window_seconds', 10)
    now = time.time()
    timestamps = state.get('prompt_timestamps', {})
    ts = [t for t in timestamps.get(session_id, []) if now - t < window]
    ts.append(now)
    timestamps[session_id] = ts
    state['prompt_timestamps'] = timestamps
    if len(ts) >= threshold:
        category = 'user.spam'

# 특수 처리: PostToolUseFailure는 Bash 도구 실패만
if event == 'PostToolUseFailure':
    if event_data.get('tool_name') != 'Bash':
        sys.exit(0)

# Subagent suppress 옵션
if event == 'SubagentStop' and cfg.get('suppress_subagent_complete', False):
    sys.exit(0)

if not category:
    json.dump(state, open(STATE_FILE, 'w'))
    sys.exit(0)

# 카테고리 비활성화 확인
if not cats_enabled.get(category, True):
    json.dump(state, open(STATE_FILE, 'w'))
    sys.exit(0)

# 활성 팩 결정 (path_rules > default_pack)
pack = cfg.get('default_pack', 'cromaiping_default')
cwd = event_data.get('cwd', '') or os.getcwd()

# path_rules 적용
import fnmatch
for rule in cfg.get('path_rules', []):
    if fnmatch.fnmatch(cwd, rule.get('pattern', '')):
        pack = rule.get('pack', pack)
        break

# 매니페스트 로드
manifest_path = os.path.join(CROMAIPING_DIR, 'packs', pack, 'openpeon.json')
if not os.path.exists(manifest_path):
    sys.exit(0)
try:
    manifest = json.load(open(manifest_path))
except Exception:
    sys.exit(0)

# 카테고리에서 사운드 선택
sounds = manifest.get('categories', {}).get(category, {}).get('sounds', [])
if not sounds:
    # category_aliases 확인
    for alias, cesp in manifest.get('category_aliases', {}).items():
        if cesp == category:
            sounds = manifest.get('categories', {}).get(alias, {}).get('sounds', [])
            if sounds:
                break

if not sounds:
    sys.exit(0)

# 직전 사운드 회피
last_played = state.get('last_played', {}).get(category, '')
candidates = [s for s in sounds if s.get('file') != last_played] or sounds
chosen = random.choice(candidates)
file_path = os.path.join(CROMAIPING_DIR, 'packs', pack, chosen['file'])

# 상태 업데이트
state.setdefault('last_played', {})[category] = chosen.get('file', '')
state['last_event'] = {'event': event, 'category': category, 'pack': pack, 'time': time.time()}
try:
    json.dump(state, open(STATE_FILE, 'w'))
except Exception:
    pass

# 출력 (bash가 받아서 재생)
volume = cfg.get('volume', 0.5)
notify_msg = chosen.get('label', '')
print(f"PLAY={file_path}")
print(f"VOL={volume}")
print(f"LABEL={notify_msg}")
print(f"NOTIFY={'1' if cfg.get('desktop_notifications', True) else '0'}")
PYEOF
)

# Python 결과 파싱
PLAY_FILE=""
VOL="0.5"
LABEL=""
NOTIFY="0"
while IFS='=' read -r key val; do
  case "$key" in
    PLAY) PLAY_FILE="$val" ;;
    VOL) VOL="$val" ;;
    LABEL) LABEL="$val" ;;
    NOTIFY) NOTIFY="$val" ;;
  esac
done <<< "$RESULT"

# 사운드 재생
[ -n "$PLAY_FILE" ] && [ -f "$PLAY_FILE" ] && play_sound "$PLAY_FILE" "$VOL"

# 데스크톱 알림 (옵션)
[ "$NOTIFY" = "1" ] && [ -n "$LABEL" ] && notify "$LABEL"

exit 0
