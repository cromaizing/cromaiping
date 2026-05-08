#!/bin/bash
# 크로마이핑 Windsurf IDE (Cascade) 어댑터
# Windsurf hook 이벤트를 cromaiping.sh의 stdin JSON으로 변환
#
# 셋업: ~/.codeium/windsurf/hooks.json 또는 .windsurf/hooks.json 에 추가:
#   {
#     "hooks": {
#       "post_cascade_response": [
#         { "command": "bash ~/.claude/hooks/cromaiping/adapters/windsurf.sh post_cascade_response", "show_output": false }
#       ],
#       "pre_user_prompt": [
#         { "command": "bash ~/.claude/hooks/cromaiping/adapters/windsurf.sh pre_user_prompt", "show_output": false }
#       ],
#       "post_write_code": [
#         { "command": "bash ~/.claude/hooks/cromaiping/adapters/windsurf.sh post_write_code", "show_output": false }
#       ],
#       "post_run_command": [
#         { "command": "bash ~/.claude/hooks/cromaiping/adapters/windsurf.sh post_run_command", "show_output": false }
#       ]
#     }
#   }
set -euo pipefail

CROMAIPING_DIR="${CLAUDE_CROMAIPING_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping}"

WINDSURF_EVENT="${1:-post_cascade_response}"

# Windsurf는 stdin으로 컨텍스트 JSON 보내지만 우리는 사용 X (drain)
cat > /dev/null

# Windsurf 이벤트 → CESP 매핑
case "$WINDSURF_EVENT" in
  post_cascade_response)
    EVENT="Stop" ;;                      # Cascade 응답 완료 → task.complete
  pre_user_prompt)
    # 첫 프롬프트면 SessionStart (인사), 이후엔 UserPromptSubmit (spam 감지용)
    SESSION_MARKER="$CROMAIPING_DIR/.windsurf-session-${PPID:-$$}"
    find "$CROMAIPING_DIR" -name ".windsurf-session-*" -mtime +0 -delete 2>/dev/null
    if [ ! -f "$SESSION_MARKER" ]; then
      touch "$SESSION_MARKER"
      EVENT="SessionStart"
    else
      EVENT="UserPromptSubmit"
    fi ;;
  post_write_code)
    EVENT="Stop" ;;                      # 코드 작성 완료 → task.complete
  post_run_command)
    EVENT="Stop" ;;                      # 명령 실행 완료 → task.complete
  *)
    exit 0 ;;                            # 알 수 없는 이벤트 스킵
esac

SESSION_ID="windsurf-${PPID:-$$}"
CWD="${PWD}"

_CE="$EVENT" _CC="$CWD" _CS="$SESSION_ID" python3 -c "
import json, os
print(json.dumps({
    'hook_event_name': os.environ['_CE'],
    'notification_type': '',
    'cwd': os.environ['_CC'],
    'session_id': os.environ['_CS'],
    'permission_mode': '',
    'source': 'windsurf',
}))
" | bash "$CROMAIPING_DIR/cromaiping.sh"
