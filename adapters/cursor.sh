#!/bin/bash
# 크로마이핑 Cursor IDE 어댑터
# Cursor의 hook 이벤트를 cromaiping.sh의 표준 stdin JSON으로 변환
#
# 셋업: ~/.cursor/hooks.json 에 다음 추가:
#   {
#     "hooks": [
#       {
#         "event": "stop",
#         "command": "bash ~/.claude/hooks/cromaiping/adapters/cursor.sh stop"
#       },
#       {
#         "event": "beforeShellExecution",
#         "command": "bash ~/.claude/hooks/cromaiping/adapters/cursor.sh beforeShellExecution"
#       },
#       {
#         "event": "afterFileEdit",
#         "command": "bash ~/.claude/hooks/cromaiping/adapters/cursor.sh afterFileEdit"
#       }
#     ]
#   }
set -euo pipefail

# CROMAIPING_DIR 해석 (다중 위치 fallback)
_resolve_cromaiping_dir() {
  local candidates=(
    "${CROMAIPING_DIR:-}"
    "${CLAUDE_CROMAIPING_DIR:-}"
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping"
    "$HOME/.cromaiping"
  )
  for dir in "${candidates[@]}"; do
    if [ -n "$dir" ] && [ -f "$dir/cromaiping.sh" ]; then
      echo "$dir"
      return
    fi
  done
  echo "[cromaiping/cursor] ERROR: cromaiping.sh를 찾을 수 없음" >&2
  echo "[cromaiping/cursor] 시도한 경로: CROMAIPING_DIR, CLAUDE_CROMAIPING_DIR, ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping, $HOME/.cromaiping" >&2
  exit 1
}

CROMAIPING_DIR="$(_resolve_cromaiping_dir)"
CURSOR_EVENT="${1:-stop}"

# Cursor 이벤트 → CESP 매핑
case "$CURSOR_EVENT" in
  stop)
    EVENT="Stop" ;;                          # 작업 완료 → task.complete
  beforeShellExecution)
    EVENT="UserPromptSubmit" ;;              # 사용자 명령 직전 → task.acknowledge
  beforeMCPExecution)
    EVENT="UserPromptSubmit" ;;              # MCP 호출 직전 → task.acknowledge
  afterFileEdit)
    EVENT="Stop" ;;                          # 파일 편집 완료 → task.complete
  beforeReadFile)
    exit 0 ;;                                # 매우 자주 발생 — 스킵
  *)
    EVENT="Stop" ;;
esac

# Cursor stdin JSON 파싱 (jq 대신 python3 — 의존성 최소화)
INPUT=$(cat)
export INPUT_RAW="$INPUT" EVENT_NAME="$EVENT"

python3 <<'PYEOF' | bash "$CROMAIPING_DIR/cromaiping.sh"
import json, os, sys

raw = os.environ.get('INPUT_RAW', '{}')
event = os.environ.get('EVENT_NAME', 'Stop')

try:
    data = json.loads(raw) if raw.strip() else {}
except Exception:
    data = {}

# Cursor는 conversation_id를 사용 (Claude Code의 session_id 대신)
session_id = data.get('conversation_id') or f"cursor-{os.getpid()}"

# Cursor는 workspace_roots 배열 (Claude Code의 cwd 대신)
cwd = ''
if isinstance(data.get('workspace_roots'), list) and data['workspace_roots']:
    cwd = data['workspace_roots'][0]
elif data.get('cwd'):
    cwd = data['cwd']
else:
    cwd = os.getcwd()

# cromaiping.sh가 기대하는 표준 형식으로 변환
output = {
    'hook_event_name': event,
    'notification_type': '',
    'cwd': cwd,
    'session_id': session_id,
    'permission_mode': '',
    'source': 'cursor'
}
print(json.dumps(output, ensure_ascii=False))
PYEOF
