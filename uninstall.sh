#!/bin/bash
# 크로마이핑 (Cromaiping) 제거 스크립트
set -euo pipefail

INSTALL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping"
SETTINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

GREEN="\033[32m"; BLUE="\033[34m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${BLUE}ℹ${RESET}  $*"; }
ok()    { echo -e "${GREEN}✓${RESET}  $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET}  $*"; }

cat <<'BANNER'

  크로마이핑 (Cromaiping) 제거

BANNER

# ─────────────────────────────────────────────
# 확인
# ─────────────────────────────────────────────
read -p "정말로 크로마이핑을 제거하시겠습니까? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  info "취소됨"
  exit 0
fi

# 사운드 팩 보존 옵션
KEEP_PACKS=0
read -p "다운로드한 사운드 팩을 보존하시겠습니까? [Y/n]: " -n 1 -r
echo
[[ ! $REPLY =~ ^[Nn]$ ]] && KEEP_PACKS=1

# ─────────────────────────────────────────────
# settings.json에서 훅 제거
# ─────────────────────────────────────────────
if [ -f "$SETTINGS_FILE" ]; then
  info "Claude Code 훅 제거 중..."
  python3 <<PYEOF
import json, os
path = "$SETTINGS_FILE"
with open(path) as f:
    data = json.load(f)

removed = 0
for event, entries in list(data.get("hooks", {}).items()):
    cleaned = []
    for entry in entries:
        hooks = entry.get("hooks", [])
        filtered = [h for h in hooks if "cromaiping" not in h.get("command", "")]
        if len(filtered) != len(hooks):
            removed += len(hooks) - len(filtered)
            entry = {**entry, "hooks": filtered}
        if entry.get("hooks"):
            cleaned.append(entry)
    if cleaned:
        data["hooks"][event] = cleaned
    else:
        del data["hooks"][event]

with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"✓ {removed}개 훅 제거")
PYEOF
fi

# ─────────────────────────────────────────────
# CLI symlink 제거
# ─────────────────────────────────────────────
for d in "$HOME/.local/bin" "/usr/local/bin"; do
  if [ -L "$d/cromaiping" ]; then
    rm -f "$d/cromaiping"
    ok "$d/cromaiping 제거"
  fi
done

# ─────────────────────────────────────────────
# 디렉토리 제거
# ─────────────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
  if [ "$KEEP_PACKS" = "1" ] && [ -d "$INSTALL_DIR/packs" ]; then
    BACKUP_DIR="$HOME/cromaiping-packs-backup-$(date +%Y%m%d%H%M%S)"
    mv "$INSTALL_DIR/packs" "$BACKUP_DIR"
    info "팩 백업: $BACKUP_DIR"
  fi
  rm -rf "$INSTALL_DIR"
  ok "$INSTALL_DIR 제거"
fi

ok "크로마이핑 제거 완료"
