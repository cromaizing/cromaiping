#!/bin/bash
# 크로마이핑 OpenClaw 게이트웨이 어댑터
# OpenClaw 이벤트를 cromaiping.sh의 stdin JSON으로 변환
#
# 셋업: OpenClaw skill에 play.sh로 추가하거나, 직접 호출:
#   bash ~/.claude/hooks/cromaiping/adapters/openclaw.sh <event>
#
# 핵심 이벤트:
#   session.start    — 세션 시작
#   task.complete    — 작업 완료
#   task.error       — 에러
#   input.required   — 사용자 입력 필요
#   task.acknowledge — 작업 수락
#   resource.limit   — 리소스 한계 (rate limit, token quota)
#
# 확장 이벤트:
#   user.spam        — 빠른 입력
#   session.end      — 세션 종료
#   task.progress    — 진행 중
#
# 또는 Claude Code PascalCase 그대로:
#   SessionStart, Stop, Notification, UserPromptSubmit
set -euo pipefail

CROMAIPING_DIR="${CLAUDE_CROMAIPING_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping}"
[ -d "$CROMAIPING_DIR" ] || CROMAIPING_DIR="$HOME/.cromaiping"

if [ ! -f "$CROMAIPING_DIR/cromaiping.sh" ]; then
  echo "크로마이핑 미설치. 설치: brew install cromaizing/tap/cromaiping" >&2
  exit 1
fi

OC_EVENT="${1:-task.complete}"
NTYPE=""

case "$OC_EVENT" in
  session.start|greeting|ready|heartbeat.first)
    EVENT="SessionStart" ;;
  task.complete|complete|done|deployed|merged)
    EVENT="Stop" ;;
  task.acknowledge|acknowledge|ack|building|working)
    EVENT="UserPromptSubmit" ;;
  task.error|error|fail|crash|build.failed)
    EVENT="PostToolUseFailure" ;;
  input.required|permission|input|waiting|blocked|approval)
    EVENT="Notification"
    NTYPE="permission_prompt" ;;
  resource.limit|ratelimit|rate.limit|quota|fallback|throttled|token.limit)
    EVENT="Notification"
    NTYPE="resource_limit" ;;
  user.spam|annoyed|spam)
    EVENT="UserPromptSubmit" ;;
  session.end|disconnect|shutdown|goodbye)
    EVENT="Stop" ;;
  task.progress|progress|running|backfill|syncing)
    EVENT="Notification"
    NTYPE="progress" ;;
  SessionStart|Stop|Notification|UserPromptSubmit|PermissionRequest|PostToolUseFailure|SubagentStart|SessionEnd)
    EVENT="$OC_EVENT" ;;
  *)
    EVENT="Stop" ;;
esac

SESSION_ID="openclaw-${OPENCLAW_SESSION_ID:-$$}"

# JSON 빌드 (jq 없으면 printf, 의존성 최소)
if command -v jq &>/dev/null; then
  jq -nc \
    --arg hook "$EVENT" \
    --arg ntype "$NTYPE" \
    --arg cwd "$PWD" \
    --arg sid "$SESSION_ID" \
    '{hook_event_name:$hook, notification_type:$ntype, cwd:$cwd, session_id:$sid, permission_mode:"", source:"openclaw"}'
else
  printf '{"hook_event_name":"%s","notification_type":"%s","cwd":"%s","session_id":"%s","permission_mode":"","source":"openclaw"}\n' \
    "$EVENT" "$NTYPE" "$PWD" "$SESSION_ID"
fi | bash "$CROMAIPING_DIR/cromaiping.sh"
