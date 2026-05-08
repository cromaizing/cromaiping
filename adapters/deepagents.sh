#!/bin/bash
# 크로마이핑 deepagents-cli 어댑터
# deepagents의 dotted event명을 cromaiping.sh PascalCase로 변환
#
# 셋업: ~/.deepagents/hooks.json 에 추가:
#   {
#     "hooks": [
#       {
#         "command": ["bash", "/absolute/path/to/.claude/hooks/cromaiping/adapters/deepagents.sh"],
#         "events": ["session.start", "session.end", "task.complete", "input.required",
#                    "task.error", "tool.error", "user.prompt", "permission.request", "compact"]
#       }
#     ]
#   }
#
# 참고: tool.call은 매 도구마다 발화하므로 의도적 제외.
set -euo pipefail

CROMAIPING_DIR="${CLAUDE_CROMAIPING_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping}"

# stdin JSON 파싱 + 매핑
MAPPED_JSON=$(python3 -c "
import sys, json, os

data = json.load(sys.stdin)
event = data.get('event')
if not event:
    sys.exit(0)

# deepagents 이벤트 → (PascalCase, notification_type)
remap = {
    'session.start':      ('SessionStart',      ''),
    'session.end':        ('SessionEnd',        ''),
    'task.complete':      ('Stop',              ''),
    'input.required':     ('Notification',      'permission_prompt'),
    'task.error':         ('Stop',              ''),
    'tool.error':         ('Notification',      'postToolUseFailure'),
    'user.prompt':        ('UserPromptSubmit',  ''),
    'permission.request': ('PermissionRequest', ''),
    'compact':            ('Notification',      'preCompact'),
}

mapped = remap.get(event)
if mapped is None:
    sys.exit(0)  # 알 수 없거나 의도적 스킵

tid = data.get('thread_id', str(os.getpid()))

print(json.dumps({
    'hook_event_name':  mapped[0],
    'notification_type': mapped[1],
    'cwd':              os.getcwd(),
    'session_id':       'deepagents-' + str(tid),
    'permission_mode':  '',
    'source':           'deepagents',
}))
")

if [ -n "$MAPPED_JSON" ]; then
  echo "$MAPPED_JSON" | bash "$CROMAIPING_DIR/cromaiping.sh"
fi
