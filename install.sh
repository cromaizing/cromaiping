#!/bin/bash
# 크로마이핑 (Cromaiping) 인스톨러
# 사용법:
#   curl -fsSL https://cromaizing.com/cromaiping/install.sh | bash
#   또는 로컬에서: bash install.sh
set -euo pipefail

VERSION="0.1.0"

# ─────────────────────────────────────────────
# 색상
# ─────────────────────────────────────────────
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

info()  { echo -e "${BLUE}ℹ${RESET}  $*"; }
ok()    { echo -e "${GREEN}✓${RESET}  $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET}  $*"; }
err()   { echo -e "${RED}✗${RESET}  $*" >&2; }

# ─────────────────────────────────────────────
# 배너
# ─────────────────────────────────────────────
cat <<'BANNER'

  ╔══════════════════════════════════════════╗
  ║   크로마이핑 (Cromaiping) v0.1.0         ║
  ║   AI 코딩 도구용 한국형 사운드 알림      ║
  ║   https://cromaizing.com/cromaiping      ║
  ╚══════════════════════════════════════════╝

BANNER

# ─────────────────────────────────────────────
# 플랫폼 감지
# ─────────────────────────────────────────────
case "$(uname -s)" in
  Darwin) PLATFORM="mac" ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then PLATFORM="wsl"
    else PLATFORM="linux"; fi ;;
  MSYS_NT*|MINGW*) PLATFORM="msys2" ;;
  *) err "지원하지 않는 플랫폼입니다: $(uname -s)"; exit 1 ;;
esac
info "플랫폼 감지: $PLATFORM"

# ─────────────────────────────────────────────
# 의존성 확인
# ─────────────────────────────────────────────
for cmd in python3 curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "$cmd 가 필요합니다. 설치 후 다시 시도해주세요."
    exit 1
  fi
done
ok "의존성 확인 완료"

# ─────────────────────────────────────────────
# 설치 위치 결정
# ─────────────────────────────────────────────
INSTALL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping"
SETTINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

info "설치 위치: $INSTALL_DIR"
info "설정 파일: $SETTINGS_FILE"

# ─────────────────────────────────────────────
# 디렉토리 생성
# ─────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"/{scripts,adapters,packs,logs}

# ─────────────────────────────────────────────
# 파일 복사 또는 원격 다운로드
# ─────────────────────────────────────────────
TARBALL_URL="${CROMAIPING_TARBALL_URL:-https://cromaizing.com/cromaiping/cromaiping-latest.tar.gz}"

# curl | bash 로 실행되면 BASH_SOURCE가 비어있거나 /dev/fd/...
SCRIPT_SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_SRC" ] && [ -f "$SCRIPT_SRC/cromaiping.sh" ]; then
  # 로컬 소스에서 설치
  info "로컬 소스에서 설치 중..."
  SOURCE_DIR="$SCRIPT_SRC"
else
  # 원격 다운로드 (curl | bash 시나리오)
  info "원격 소스 다운로드 중..."
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  TARBALL="$TMP_DIR/cromaiping.tar.gz"
  if ! curl -fsSL "$TARBALL_URL" -o "$TARBALL"; then
    err "다운로드 실패: $TARBALL_URL"
    err "수동 설치: git clone https://github.com/cromaizing/cromaiping && cd cromaiping && bash install.sh"
    exit 1
  fi
  tar -xzf "$TARBALL" -C "$TMP_DIR"
  SOURCE_DIR="$(find "$TMP_DIR" -maxdepth 2 -name 'cromaiping.sh' -exec dirname {} \; | head -1)"
  if [ -z "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/cromaiping.sh" ]; then
    err "tarball 구조가 올바르지 않습니다."
    exit 1
  fi
  ok "다운로드 완료"
fi

# 파일 복사
cp -f "$SOURCE_DIR/cromaiping.sh" "$INSTALL_DIR/"
cp -f "$SOURCE_DIR/VERSION" "$INSTALL_DIR/"
cp -rf "$SOURCE_DIR/scripts/." "$INSTALL_DIR/scripts/"
[ -d "$SOURCE_DIR/adapters" ] && cp -rf "$SOURCE_DIR/adapters/." "$INSTALL_DIR/adapters/" 2>/dev/null || true
[ -d "$SOURCE_DIR/packs" ] && cp -rf "$SOURCE_DIR/packs/." "$INSTALL_DIR/packs/" 2>/dev/null || true

# config.json은 기존 파일이 있으면 보존
if [ ! -f "$INSTALL_DIR/config.json" ]; then
  cp "$SOURCE_DIR/config.json" "$INSTALL_DIR/config.json"
else
  warn "기존 config.json 보존됨"
fi

chmod +x "$INSTALL_DIR/cromaiping.sh"
chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true
ok "파일 복사 완료"

# ─────────────────────────────────────────────
# Placeholder 사운드 생성 (자체 팩 제작 전까지)
# ─────────────────────────────────────────────
if [ -x "$INSTALL_DIR/scripts/gen-placeholder-sounds.sh" ]; then
  bash "$INSTALL_DIR/scripts/gen-placeholder-sounds.sh" "$INSTALL_DIR" >/dev/null 2>&1 || true
  ok "기본 사운드 준비 완료"
fi

# ─────────────────────────────────────────────
# Claude Code 훅 자동 등록
# ─────────────────────────────────────────────
info "Claude Code 훅 등록 중..."

python3 <<PYEOF
import json, os, sys

settings_path = "$SETTINGS_FILE"
hook_path = "$INSTALL_DIR/cromaiping.sh"
intercept_path = "$INSTALL_DIR/scripts/cmd-intercept.sh"

# 기존 settings.json 로드
if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            print("⚠ settings.json 파싱 실패, 백업 후 새로 생성합니다.")
            os.rename(settings_path, settings_path + ".bak")
            data = {}
else:
    data = {}

data.setdefault("hooks", {})

# 등록할 이벤트 목록
events = [
    "SessionStart", "SessionEnd", "Stop",
    "Notification", "PermissionRequest",
    "PostToolUseFailure", "PreCompact",
    "SubagentStop"
]

# 기존 크로마이핑 훅 제거 (재설치 대비)
def is_cromaiping_hook(h):
    cmd = h.get("command", "")
    return "cromaiping" in cmd

for event in events:
    existing = data["hooks"].get(event, [])
    cleaned = []
    for entry in existing:
        hooks_list = entry.get("hooks", [])
        filtered = [h for h in hooks_list if not is_cromaiping_hook(h)]
        if filtered or not hooks_list:
            entry = {**entry, "hooks": filtered}
            if entry["hooks"] or "matcher" in entry:
                cleaned.append(entry)
    data["hooks"][event] = cleaned

# UserPromptSubmit은 메인 훅 + 슬래시 인터셉터 둘 다 등록
existing = data["hooks"].get("UserPromptSubmit", [])
cleaned = []
for entry in existing:
    hooks_list = entry.get("hooks", [])
    filtered = [h for h in hooks_list if not is_cromaiping_hook(h)]
    if filtered or not hooks_list:
        entry = {**entry, "hooks": filtered}
        if entry["hooks"] or "matcher" in entry:
            cleaned.append(entry)
data["hooks"]["UserPromptSubmit"] = cleaned

# 새 훅 추가
for event in events:
    data["hooks"][event].append({
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": hook_path,
            "timeout": 10
        }]
    })

# UserPromptSubmit: 메인 훅 + 슬래시 인터셉터
data["hooks"]["UserPromptSubmit"].append({
    "matcher": "",
    "hooks": [{
        "type": "command",
        "command": hook_path,
        "timeout": 10
    }]
})
data["hooks"]["UserPromptSubmit"].append({
    "matcher": "",
    "hooks": [{
        "type": "command",
        "command": intercept_path,
        "timeout": 5
    }]
})

# 저장
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"✓ {len(events) + 1}개 이벤트 훅 등록 완료")
PYEOF

# ─────────────────────────────────────────────
# CLI 명령어 등록 (PATH에 심볼릭 링크)
# ─────────────────────────────────────────────
SHIM_DIR=""

# 1순위: PATH에 이미 있고 쓰기 가능한 디렉토리
for d in "$HOME/.local/bin" "/usr/local/bin" "/opt/homebrew/bin"; do
  if [[ ":$PATH:" == *":$d:"* ]] && [ -d "$d" ] && [ -w "$d" ]; then
    SHIM_DIR="$d"
    break
  fi
done

# 2순위: ~/.local/bin 만들고 사용 (PATH에 없어도)
if [ -z "$SHIM_DIR" ]; then
  mkdir -p "$HOME/.local/bin"
  SHIM_DIR="$HOME/.local/bin"
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    # zshrc에 PATH 추가 (중복 체크)
    SHELL_RC=""
    [ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
    [ -z "$SHELL_RC" ] && [ -f "$HOME/.bashrc" ] && SHELL_RC="$HOME/.bashrc"
    if [ -n "$SHELL_RC" ] && ! grep -q "\.local/bin" "$SHELL_RC" 2>/dev/null; then
      echo "" >> "$SHELL_RC"
      echo "# Cromaiping" >> "$SHELL_RC"
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
      info "PATH 자동 추가: $SHELL_RC (새 터미널부터 적용)"
    fi
  fi
fi

ln -sf "$INSTALL_DIR/cromaiping.sh" "$SHIM_DIR/cromaiping"
ok "CLI 명령어 등록: $SHIM_DIR/cromaiping"

# ─────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────
echo ""
ok "🎉 크로마이핑 설치가 완료되었습니다!"
echo ""
echo "  사용 시작:"
echo "    cromaiping status         # 상태 확인"
echo "    cromaiping list           # 설치된 팩 목록"
echo "    cromaiping preview        # 사운드 미리듣기"
echo ""
echo "  Claude Code 채팅에서:"
echo "    /cromaiping-help          # 도움말"
echo "    /cromaiping-status        # 상태 확인"
echo "    /cromaiping-toggle        # 음소거 토글"
echo ""
echo "  더 알아보기: https://cromaizing.com/cromaiping"
echo ""
