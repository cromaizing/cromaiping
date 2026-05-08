#!/bin/bash
# 크로마이핑 Rovo Dev CLI (Atlassian) 어댑터
# Rovo Dev event hook 이벤트명을 cromaiping.sh의 stdin JSON으로 변환
#
# Rovo Dev CLI는 이벤트명을 CLI 인자로 보냄 (stdin 아님).
#
# 셋업: ~/.rovodev/config.yml 에 추가:
#   eventHooks:
#     events:
#       - name: on_complete
#         commands:
#           - command: bash ~/.claude/hooks/cromaiping/adapters/rovodev.sh on_complete
#       - name: on_error
#         commands:
#           - command: bash ~/.claude/hooks/cromaiping/adapters/rovodev.sh on_error
#       - name: on_tool_permission
#         commands:
#           - command: bash ~/.claude/hooks/cromaiping/adapters/rovodev.sh on_tool_permission
#
# 참고: ~ 자동 확장이 안 되면 절대경로 사용.
set -euo pipefail

CROMAIPING_DIR="${CLAUDE_CROMAIPING_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping}"
[ -d "$CROMAIPING_DIR" ] || CROMAIPING_DIR="$HOME/.cromaiping"

if [ ! -f "$CROMAIPING_DIR/cromaiping.sh" ]; then
  echo "크로마이핑 미설치. 설치: brew install cromaizing/tap/cromaiping" >&2
  exit 1
fi

RD_EVENT="${1:-on_complete}"

case "$RD_EVENT" in
  on_complete)
    EVENT="Stop" ;;
  on_error)
    EVENT="PostToolUseFailure" ;;
  on_tool_permission|on_permission_request)
    EVENT="PermissionRequest" ;;
  *)
    exit 0 ;;
esac

SESSION_ID="rovodev-${ROVODEV_SESSION_ID:-$$}"

TOOL_NAME=""
ERROR_MSG=""
[ "$EVENT" = "PostToolUseFailure" ] && TOOL_NAME="Bash" && ERROR_MSG="Agent error"

if command -v jq &>/dev/null; then
  jq -nc \
    --arg hook "$EVENT" \
    --arg cwd "$PWD" \
    --arg sid "$SESSION_ID" \
    --arg tn "$TOOL_NAME" \
    --arg err "$ERROR_MSG" \
    '{hook_event_name:$hook, cwd:$cwd, session_id:$sid, permission_mode:"", source:"rovodev", tool_name:$tn, error:$err}'
else
  printf '{"hook_event_name":"%s","cwd":"%s","session_id":"%s","permission_mode":"","source":"rovodev","tool_name":"%s","error":"%s"}\n' \
    "$EVENT" "$PWD" "$SESSION_ID" "$TOOL_NAME" "$ERROR_MSG"
fi | bash "$CROMAIPING_DIR/cromaiping.sh"
