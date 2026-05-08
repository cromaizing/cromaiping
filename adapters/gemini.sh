#!/bin/bash
# 크로마이핑 Gemini CLI 어댑터
# Gemini CLI hook 이벤트를 cromaiping.sh의 stdin JSON으로 변환
#
# 셋업: ~/.gemini/settings.json 에 추가:
#   {
#     "hooks": {
#       "SessionStart": [
#         { "matcher": "startup", "hooks": [
#           { "name": "cromaiping-start", "type": "command",
#             "command": "bash ~/.claude/hooks/cromaiping/adapters/gemini.sh SessionStart" }
#         ]}
#       ],
#       "AfterAgent": [
#         { "matcher": "*", "hooks": [
#           { "name": "cromaiping-after-agent", "type": "command",
#             "command": "bash ~/.claude/hooks/cromaiping/adapters/gemini.sh AfterAgent" }
#         ]}
#       ],
#       "AfterTool": [
#         { "matcher": "*", "hooks": [
#           { "name": "cromaiping-after-tool", "type": "command",
#             "command": "bash ~/.claude/hooks/cromaiping/adapters/gemini.sh AfterTool" }
#         ]}
#       ],
#       "Notification": [
#         { "matcher": "*", "hooks": [
#           { "name": "cromaiping-notif", "type": "command",
#             "command": "bash ~/.claude/hooks/cromaiping/adapters/gemini.sh Notification" }
#         ]}
#       ]
#     }
#   }
set -euo pipefail

# cromaiping.sh 위치 (로컬/글로벌 설치 모두 대응)
CROMAIPING_DIR="${CLAUDE_CROMAIPING_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ ! -f "$CROMAIPING_DIR/cromaiping.sh" ] && CROMAIPING_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping"

GEMINI_EVENT_TYPE="${1:-SessionStart}"

# Gemini CLI는 stdin으로 JSON 보냄
INPUT=$(cat)

# 공통 필드 추출
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('session_id', ''))" 2>/dev/null || echo "")
[ -z "$SESSION_ID" ] && SESSION_ID="gemini-$$"
CWD=$(echo "$INPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('cwd', ''))" 2>/dev/null || echo "$PWD")

# Gemini 이벤트 → CESP 매핑
EVENT=""
case "$GEMINI_EVENT_TYPE" in
  SessionStart)
    EVENT="SessionStart" ;;
  AfterAgent)
    EVENT="Stop" ;;
  Notification)
    EVENT="Notification" ;;
  AfterTool)
    # exit_code 검사로 성공/실패 구분
    EXIT_CODE=$(echo "$INPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('exit_code', 0))" 2>/dev/null || echo 0)
    if [ "$EXIT_CODE" -ne 0 ]; then
      EVENT="PostToolUseFailure"
    else
      EVENT="Stop"
    fi ;;
  *)
    # 알 수 없는 이벤트 → 빈 JSON 반환 후 종료
    echo "{}"
    exit 0 ;;
esac

# cromaiping.sh로 forward
export GEM_INPUT="$INPUT" GEM_EVENT="$EVENT" GEM_SESSION="$SESSION_ID" GEM_CWD="$CWD"
python3 <<'PYEOF' | bash "$CROMAIPING_DIR/cromaiping.sh" >/dev/null 2>&1 || true
import json, os, sys

raw = os.environ.get('GEM_INPUT', '{}')
event = os.environ.get('GEM_EVENT', 'Stop')
session = os.environ.get('GEM_SESSION', 'gemini')
cwd = os.environ.get('GEM_CWD', '/')

try:
    input_data = json.loads(raw) if raw.strip() else {}
except Exception:
    input_data = {}

payload = {
    'hook_event_name': event,
    'notification_type': '',
    'cwd': cwd,
    'session_id': session,
    'permission_mode': '',
    'source': 'gemini'
}

# AfterTool 실패 시 Bash 도구로 표시 (cromaiping이 task.error로 처리)
if event == 'PostToolUseFailure':
    payload['tool_name'] = 'Bash'
    payload['error'] = input_data.get('stderr', 'Tool failed')

print(json.dumps(payload))
PYEOF

# Gemini CLI는 hook 응답으로 빈 JSON 기대
echo "{}"
