#!/bin/bash
# cromaiping adapter for OpenCode
# Installs the thin TypeScript adapter that routes events through cromaiping.sh.
#
# Requires cromaiping installed first:
#   brew install cromaizing/tap/cromaiping
#   # or: curl -fsSL cromaizing.com/cromaiping/install | bash
#
# Install this adapter:
#   bash adapters/opencode.sh
#
# Or directly:
#   curl -fsSL https://raw.githubusercontent.com/Cromaizing/cromaiping/main/adapters/opencode.sh | bash
#
# Uninstall:
#   bash adapters/opencode.sh --uninstall

set -euo pipefail

PLUGIN_URL="https://raw.githubusercontent.com/Cromaizing/cromaiping/main/adapters/opencode/cromaiping.ts"
OPENCODE_PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins"
PEON_SH_CANDIDATES=(
  "$HOME/.claude/hooks/cromaiping/cromaiping.sh"
  "$HOME/.openclaw/hooks/cromaiping/cromaiping.sh"
)

BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RESET=$'\033[0m'

info()  { printf "%s>%s %s\n" "$GREEN" "$RESET" "$*"; }
warn()  { printf "%s!%s %s\n" "$YELLOW" "$RESET" "$*"; }
error() { printf "%sx%s %s\n" "$RED" "$RESET" "$*" >&2; }

# --- Uninstall ---
if [ "${1:-}" = "--uninstall" ]; then
  info "Uninstalling cromaiping adapter from OpenCode..."
  rm -f "$OPENCODE_PLUGINS_DIR/cromaiping.ts"
  info "Adapter removed."
  exit 0
fi

# --- Preflight: find cromaiping.sh ---
PEON_SH=""
for candidate in "${PEON_SH_CANDIDATES[@]}"; do
  if [ -f "$candidate" ]; then
    PEON_SH="$candidate"
    break
  fi
done

if [ -z "$PEON_SH" ]; then
  error "cromaiping.sh not found. Install cromaiping first:"
  error "  brew install cromaizing/tap/cromaiping"
  error "  # or: curl -fsSL cromaizing.com/cromaiping/install | bash"
  exit 1
fi

if ! command -v curl &>/dev/null; then
  error "curl is required but not found."
  exit 1
fi

# --- Install adapter ---
info "Installing cromaiping adapter for OpenCode..."

mkdir -p "$OPENCODE_PLUGINS_DIR"
rm -f "$OPENCODE_PLUGINS_DIR/cromaiping.ts"

info "Downloading adapter..."
curl -fsSL "$PLUGIN_URL" -o "$OPENCODE_PLUGINS_DIR/cromaiping.ts"
info "Adapter installed to $OPENCODE_PLUGINS_DIR/cromaiping.ts"

# --- Done ---
echo ""
info "${BOLD}cromaiping adapter installed for OpenCode!${RESET}"
echo ""
printf "  %sAdapter:%s %s\n" "$DIM" "$RESET" "$OPENCODE_PLUGINS_DIR/cromaiping.ts"
printf "  %scromaiping.sh:%s %s\n" "$DIM" "$RESET" "$PEON_SH"
echo ""
info "Restart OpenCode to activate. All cromaiping features now available."
info "Configure: peon config | peon trainer on | peon packs list"
