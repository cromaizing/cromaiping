#!/bin/bash
# 크로마이핑 Kiro CLI (Amazon) 어댑터
# Kiro hook 이벤트를 cromaiping.sh의 stdin JSON으로 변환
#
# Kiro는 Claude Code와 거의 동일한 stdin JSON hook 시스템 사용.
# 이벤트명만 camelCase → PascalCase 변환 필요.
#
# 셋업: ~/.kiro/agents/cromaiping.json 생성:
#   {
#     "hooks": {
#       "agentSpawn": [
#         { "command": "bash ~/.claude/hooks/cromaiping/adapters/kiro.sh" }
#       ],
#       "userPromptSubmit": [
#         { "command": "bash ~/.claude/hooks/cromaiping/adapters/kiro.sh" }
#       ],
#       "stop": [
#         { "command": "bash ~/.claude/hooks/cromaiping/adapters/kiro.sh" }
#       ]
#     }
#   }
#
# 참고: preToolUse / postToolUse는 매 도구 호출마다 발화하므로 의도적 제외.
set -euo pipefail

CROMAIPING_DIR="${CLAUDE_CROMAIPING_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping}"

# Kiro stdin JSON → cromaiping.sh 형식 변환
MAPPED_JSON=$(python3 -c "
import sys, json, os

data = json.load(sys.stdin)
event = data.get('hook_event_name', 'stop')

# Kiro camelCase → cromaiping PascalCase
remap = {
    'agentSpawn': 'SessionStart',
    'userPromptSubmit': 'UserPromptSubmit',
    'stop': 'Stop',
}

mapped = remap.get(event)
if mapped is None:
    sys.exit(0)  # 알 수 없거나 의도적으로 스킵된 이벤트

sid = data.get('session_id', str(os.getpid()))
cwd = data.get('cwd', os.getcwd())

print(json.dumps({
    'hook_event_name': mapped,
    'notification_type': '',
    'cwd': cwd,
    'session_id': 'kiro-' + str(sid),
    'permission_mode': data.get('permission_mode', ''),
    'source': 'kiro',
}))
")

# Python이 매핑된 결과를 출력했을 때만 cromaiping.sh로 forward
if [ -n "$MAPPED_JSON" ]; then
  echo "$MAPPED_JSON" | bash "$CROMAIPING_DIR/cromaiping.sh"
fi
