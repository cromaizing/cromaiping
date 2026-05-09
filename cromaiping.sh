#!/bin/bash
# 크로마이핑 (Cromaiping) — AI 코딩 도구용 한국형 사운드 알림
# CESP v1.0 호환 / peon-ping 아키텍처 기반
# 메인 훅 핸들러: stdin으로 받은 이벤트 JSON을 파싱해 카테고리 매핑 후 사운드 재생
set -uo pipefail

VERSION="0.1.0"

# ─────────────────────────────────────────────
# 경로 해석 (Homebrew/Nix/표준 설치 + symlink 모두 지원)
# ─────────────────────────────────────────────
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
CROMAIPING_DIR="${CROMAIPING_DIR:-$SCRIPT_DIR}"

# 설정/상태 파일은 사용자 홈에 (read-only 설치 대비)
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping"
[ -d "$CONFIG_DIR" ] || CONFIG_DIR="$CROMAIPING_DIR"
CONFIG_FILE="$CONFIG_DIR/config.json"
STATE_FILE="$CONFIG_DIR/.state.json"
LOG_FILE="$CONFIG_DIR/cromaiping.log"

# ─────────────────────────────────────────────
# 플랫폼 감지
# ─────────────────────────────────────────────
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then echo "wsl"
      elif [ -n "${SSH_CONNECTION:-}" ]; then echo "ssh"
      else echo "linux"; fi ;;
    MSYS_NT*|MINGW*) echo "msys2" ;;
    *) echo "unknown" ;;
  esac
}
PLATFORM="${CROMAIPING_PLATFORM:-$(detect_platform)}"

# ─────────────────────────────────────────────
# 로깅 (디버그 모드일 때만)
# ─────────────────────────────────────────────
log() {
  [ "${CROMAIPING_DEBUG:-0}" = "1" ] || return 0
  echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# 사운드 재생 (플랫폼별)
# ─────────────────────────────────────────────
play_sound() {
  local file="$1" vol="${2:-0.5}"
  [ -f "$file" ] || { log "play: file_not_found $file"; return 1; }

  case "$PLATFORM" in
    mac)
      # 우선순위: 자체 컴파일된 play 바이너리 → afplay
      if [ -x "$CROMAIPING_DIR/scripts/play" ]; then
        nohup "$CROMAIPING_DIR/scripts/play" -v "$vol" "$file" >/dev/null 2>&1 &
      else
        nohup afplay -v "$vol" "$file" >/dev/null 2>&1 &
      fi ;;
    linux|wsl)
      for player in pw-play paplay ffplay mpv play aplay; do
        if command -v "$player" >/dev/null 2>&1; then
          case "$player" in
            ffplay) nohup ffplay -nodisp -autoexit -volume $(printf '%.0f' "$(echo "$vol*100" | bc -l)") "$file" >/dev/null 2>&1 & ;;
            mpv) nohup mpv --no-video --volume="$(echo "$vol*100" | bc -l)" "$file" >/dev/null 2>&1 & ;;
            *) nohup "$player" "$file" >/dev/null 2>&1 & ;;
          esac
          break
        fi
      done ;;
    msys2)
      command -v powershell.exe >/dev/null 2>&1 && \
        powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '$file').PlaySync()" >/dev/null 2>&1 & ;;
  esac
  log "play: $file vol=$vol"
}

# ─────────────────────────────────────────────
# 데스크톱 알림 (플랫폼별)
# ─────────────────────────────────────────────
notify() {
  local msg="$1" title="${2:-크로마이핑}" pack="${3:-}"
  case "$PLATFORM" in
    mac)
      # 활성 팩 매니페스트에서 overlay 정보 추출
      local pack_dir="$CROMAIPING_DIR/packs/$pack"
      local manifest="$pack_dir/openpeon.json"
      local overlay_script="$CROMAIPING_DIR/scripts/pack-overlay.js"

      if [ -n "$pack" ] && [ -f "$manifest" ] && [ -f "$overlay_script" ]; then
        # 매니페스트의 overlay 정보 추출 (peon-ping 패턴)
        local overlay_info=$(python3 -c "
import json
try:
    m = json.load(open('$manifest'))
    ov = m.get('overlay', {})
    icon = ov.get('icon') or m.get('icon', '')
    color = ov.get('color', 'violet')
    duration = ov.get('duration_seconds', 4.5)
    position = ov.get('position', 'top-right')
    if icon and not icon.startswith('/'):
        icon = '$pack_dir/' + icon
    print(f'{icon}|{color}|{duration}|{position}')
except Exception:
    print('||||')
" 2>/dev/null)

        local overlay_gif=$(echo "$overlay_info" | cut -d'|' -f1)
        local overlay_color=$(echo "$overlay_info" | cut -d'|' -f2)
        local overlay_dur=$(echo "$overlay_info" | cut -d'|' -f3)
        local overlay_pos=$(echo "$overlay_info" | cut -d'|' -f4)

        if [ -n "$overlay_gif" ] && [ -f "$overlay_gif" ]; then
          # 백그라운드로 띄움 (hook context detach)
          (osascript -l JavaScript "$overlay_script" \
            "$overlay_gif" "$msg" "$overlay_color" "$overlay_dur" "$overlay_pos" \
            >/dev/null 2>&1 &) </dev/null
          return 0
        fi
      fi

      # Fallback: 기본 macOS 알림
      osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null & ;;
    linux)
      command -v notify-send >/dev/null 2>&1 && notify-send "$title" "$msg" 2>/dev/null & ;;
  esac
}

# ─────────────────────────────────────────────
# 크로마이핑 레지스트리 설정
# ─────────────────────────────────────────────
# 1순위: 자체 레지스트리 (cromaizing.com 호스팅)
# 2순위: 외부 공개 레지스트리 (백엔드 디테일, 사용자에게 노출 X)
REGISTRY_URL_PRIMARY="${CROMAIPING_REGISTRY:-https://cromaizing.com/cromaiping/registry.json}"
REGISTRY_URL_FALLBACK="${CROMAIPING_REGISTRY_FALLBACK:-https://peonping.github.io/registry/index.json}"
REGISTRY_CACHE_DIR="$CONFIG_DIR/.registry-cache"
REGISTRY_CACHE_TTL=3600  # 1시간

# 레지스트리 가져오기 (캐시 사용)
fetch_registry() {
  mkdir -p "$REGISTRY_CACHE_DIR"
  local cache_file="$REGISTRY_CACHE_DIR/index.json"

  # 캐시가 신선하면 사용
  if [ -f "$cache_file" ]; then
    local age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [ "$age" -lt "$REGISTRY_CACHE_TTL" ]; then
      cat "$cache_file"
      return 0
    fi
  fi

  # 1순위 시도
  if curl -fsSL --max-time 10 "$REGISTRY_URL_PRIMARY" -o "$cache_file.tmp" 2>/dev/null; then
    mv "$cache_file.tmp" "$cache_file"
    cat "$cache_file"
    return 0
  fi

  # 2순위 (외부) 시도 — 사용자에게는 "기본 레지스트리"로 표시
  if curl -fsSL --max-time 10 "$REGISTRY_URL_FALLBACK" -o "$cache_file.tmp" 2>/dev/null; then
    mv "$cache_file.tmp" "$cache_file"
    cat "$cache_file"
    return 0
  fi

  # 캐시라도 있으면 stale 사용
  [ -f "$cache_file" ] && cat "$cache_file" && return 0
  return 1
}

# 팩 레지스트리에서 검색 (Python으로 JSON 파싱)
registry_lookup() {
  local pack_name="$1"
  fetch_registry | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    packs = data.get('packs', [])
    for p in packs:
        if p.get('name') == '$pack_name':
            print(json.dumps(p, ensure_ascii=False))
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
"
}

# 외부 GitHub URL을 cromaizing 도메인 표기로 위장 (UI 출력용)
# 실제 다운로드는 원본 URL 사용
display_source() {
  echo "크로마이핑 레지스트리"
}

# 팩 다운로드 + 추출 + 검증
download_pack() {
  local pack_json="$1"
  local pack_name=$(echo "$pack_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
  local source_repo=$(echo "$pack_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('source_repo',''))")
  local source_ref=$(echo "$pack_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('source_ref','main'))")
  local source_path=$(echo "$pack_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('source_path',''))")
  local download_url=$(echo "$pack_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('download_url',''))")

  local pack_dir="$CROMAIPING_DIR/packs/$pack_name"
  local tmp_dir=$(mktemp -d)

  # 다운로드 URL 결정
  local url=""
  if [ -n "$download_url" ]; then
    url="$download_url"
  elif [ -n "$source_repo" ]; then
    url="https://github.com/${source_repo}/archive/refs/tags/${source_ref}.tar.gz"
    # 태그 없으면 브랜치 시도
    if ! curl -fsIL --max-time 5 "$url" >/dev/null 2>&1; then
      url="https://github.com/${source_repo}/archive/${source_ref}.tar.gz"
    fi
  else
    rm -rf "$tmp_dir"
    echo "❌ 다운로드 정보 없음" >&2
    return 1
  fi

  # 다운로드
  echo "  📥 다운로드 중..."
  if ! curl -fsSL --max-time 60 "$url" -o "$tmp_dir/pack.tar.gz" 2>/dev/null; then
    rm -rf "$tmp_dir"
    echo "  ❌ 다운로드 실패" >&2
    return 1
  fi

  # 압축 해제
  echo "  📦 압축 해제 중..."
  if ! tar -xzf "$tmp_dir/pack.tar.gz" -C "$tmp_dir" 2>/dev/null; then
    rm -rf "$tmp_dir"
    echo "  ❌ 압축 해제 실패" >&2
    return 1
  fi

  # 매니페스트 위치 찾기
  local manifest_path=""
  if [ -n "$source_path" ]; then
    manifest_path=$(find "$tmp_dir" -path "*/$source_path/openpeon.json" -type f 2>/dev/null | head -1)
  fi
  [ -z "$manifest_path" ] && manifest_path=$(find "$tmp_dir" -name "openpeon.json" -type f 2>/dev/null | head -1)

  if [ -z "$manifest_path" ] || [ ! -f "$manifest_path" ]; then
    rm -rf "$tmp_dir"
    echo "  ❌ openpeon.json 매니페스트를 찾을 수 없음" >&2
    return 1
  fi

  local pack_src_dir=$(dirname "$manifest_path")

  # 보안: 사이즈 제한 (50MB)
  local total_size=$(du -sk "$pack_src_dir" | cut -f1)
  if [ "$total_size" -gt 51200 ]; then
    rm -rf "$tmp_dir"
    echo "  ❌ 팩 크기 초과 (50MB 제한)" >&2
    return 1
  fi

  # 매니페스트 검증
  if ! python3 -c "
import json, sys
try:
    m = json.load(open('$manifest_path'))
    assert m.get('cesp_version') == '1.0', 'Invalid cesp_version'
    assert m.get('name'), 'Missing name'
    assert m.get('categories'), 'Missing categories'
except Exception as e:
    print(f'  ❌ 매니페스트 검증 실패: {e}', file=sys.stderr)
    sys.exit(1)
"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  # 오디오 매직바이트 검증
  echo "  🔍 오디오 파일 검증 중..."
  local invalid_count=0
  while IFS= read -r audio_file; do
    if [ -f "$audio_file" ]; then
      local magic=$(head -c 4 "$audio_file" | xxd -p 2>/dev/null)
      case "$magic" in
        52494646*|49443*|4f676753*|fffb*|fff3*|fff2*) ;;  # WAV (RIFF), MP3 (ID3 or sync), OGG
        *) invalid_count=$((invalid_count + 1)) ;;
      esac
    fi
  done < <(find "$pack_src_dir" -type f \( -name "*.wav" -o -name "*.mp3" -o -name "*.ogg" \))

  if [ "$invalid_count" -gt 0 ]; then
    rm -rf "$tmp_dir"
    echo "  ❌ ${invalid_count}개 오디오 파일이 유효하지 않음" >&2
    return 1
  fi

  # 기존 팩 백업
  if [ -d "$pack_dir" ]; then
    rm -rf "${pack_dir}.bak"
    mv "$pack_dir" "${pack_dir}.bak" 2>/dev/null || true
  fi

  # 설치
  mkdir -p "$pack_dir"
  cp -r "$pack_src_dir/." "$pack_dir/"

  # 백업 제거
  rm -rf "${pack_dir}.bak" 2>/dev/null || true
  rm -rf "$tmp_dir"

  return 0
}

# ─────────────────────────────────────────────
# CLI 모드 (stdin이 TTY이거나 인자가 있을 때)
# ─────────────────────────────────────────────
if [ -t 0 ] || [ $# -gt 0 ]; then
  case "${1:-help}" in
    version|--version|-v) echo "크로마이핑 v$VERSION"; exit 0 ;;
    status)
      python3 -c "
import json, os
cfg = json.load(open('$CONFIG_FILE'))
print(f'크로마이핑: {\"활성\" if cfg.get(\"enabled\", True) else \"음소거\"}')
print(f'기본 팩: {cfg.get(\"default_pack\", \"-\")}')
print(f'볼륨: {int(cfg.get(\"volume\", 0.5)*100)}%')
print(f'데스크톱 알림: {\"on\" if cfg.get(\"desktop_notifications\", True) else \"off\"}')
"
      exit 0 ;;
    pause|mute)
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['enabled'] = False
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('크로마이핑: 음소거됨')
"
      exit 0 ;;
    resume|unmute)
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['enabled'] = True
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('크로마이핑: 활성화됨')
"
      exit 0 ;;
    toggle)
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['enabled'] = not cfg.get('enabled', True)
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('크로마이핑: ' + ('활성화됨' if cfg['enabled'] else '음소거됨'))
"
      exit 0 ;;
    volume)
      shift
      if [ -n "${1:-}" ]; then
        python3 -c "
import json, sys
v = float(sys.argv[1])
v = max(0.0, min(1.0, v if v <= 1 else v/100))
cfg = json.load(open('$CONFIG_FILE'))
cfg['volume'] = v
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print(f'볼륨: {int(v*100)}%')
" "$1"
      else
        python3 -c "import json; print(f'볼륨: {int(json.load(open(\"$CONFIG_FILE\"))[\"volume\"]*100)}%')"
      fi
      exit 0 ;;
    use)
      shift
      [ -z "${1:-}" ] && { echo "사용법: cromaiping use <팩이름>"; exit 1; }
      pack_dir="$CROMAIPING_DIR/packs/$1"
      [ -d "$pack_dir" ] || { echo "팩을 찾을 수 없음: $1"; exit 1; }
      python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['default_pack'] = '$1'
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('팩이 변경됨: $1')
"
      exit 0 ;;
    list)
      echo "📦 설치된 팩:"
      for p in "$CROMAIPING_DIR/packs/"*/; do
        [ -d "$p" ] || continue
        name=$(basename "$p")
        manifest="$p/openpeon.json"
        if [ -f "$manifest" ]; then
          display=$(python3 -c "import json; print(json.load(open('$manifest')).get('display_name', '$name'))" 2>/dev/null)
          echo "  • $name — $display"
        fi
      done
      exit 0 ;;
    packs)
      shift
      packs_subcmd="${1:-list}"
      [ $# -gt 0 ] && shift
      case "$packs_subcmd" in
        list)
          # --registry 플래그면 레지스트리 목록, 아니면 설치된 팩
          if [ "${1:-}" = "--registry" ] || [ "${1:-}" = "-r" ]; then
            shift
            lang_filter=""
            for arg in "$@"; do
              case "$arg" in
                --lang=*) lang_filter="${arg#--lang=}" ;;
              esac
            done
            echo "🌐 크로마이핑 레지스트리에서 가져오는 중..."
            registry=$(fetch_registry) || { echo "❌ 레지스트리에 연결할 수 없습니다."; exit 1; }
            export REG_LANG="$lang_filter"
            echo "$registry" | python3 -c "
import json, sys, os
data = json.load(sys.stdin)
packs = data.get('packs', [])
lang = os.environ.get('REG_LANG', '')
if lang:
    packs = [p for p in packs if p.get('language', 'en') == lang]
total = len(packs)
print(f'\n📦 사용 가능한 팩: {total}개\n')
# 언어별 그룹핑
ko_packs = [p for p in packs if p.get('language') == 'ko']
other = [p for p in packs if p.get('language') != 'ko']
if ko_packs:
    print('🇰🇷 한국어')
    for p in ko_packs:
        name = p.get('name', '')
        dn = p.get('display_name', name)
        sc = p.get('sound_count', '?')
        print(f'  {name:30s} {dn} ({sc}개)')
    print()
if other and not lang:
    print(f'🌐 기타 언어 ({len(other)}개) — --lang=ko 로 한국어만 보기')
    for p in other[:30]:  # 처음 30개만
        name = p.get('name', '')
        dn = p.get('display_name', name)
        lng = p.get('language', '?')
        sc = p.get('sound_count', '?')
        print(f'  {name:30s} {dn} [{lng}] ({sc}개)')
    if len(other) > 30:
        print(f'  ... 그 외 {len(other) - 30}개. cromaiping packs search <키워드> 로 검색')
print()
print('💡 cromaiping packs install <이름>  으로 설치')
print('💡 cromaiping packs info <이름>     으로 상세 정보')
"
          else
            echo "📦 설치된 팩:"
            for p in "$CROMAIPING_DIR/packs/"*/; do
              [ -d "$p" ] || continue
              name=$(basename "$p")
              manifest="$p/openpeon.json"
              if [ -f "$manifest" ]; then
                display=$(python3 -c "import json; print(json.load(open('$manifest')).get('display_name', '$name'))" 2>/dev/null)
                echo "  • $name — $display"
              fi
            done
            echo ""
            echo "💡 더 많은 팩: cromaiping packs list --registry"
          fi
          exit 0 ;;
        search)
          [ -z "${1:-}" ] && { echo "사용법: cromaiping packs search <키워드>"; exit 1; }
          query="$1"
          echo "🔍 '$query' 검색 중..."
          registry=$(fetch_registry) || { echo "❌ 레지스트리에 연결할 수 없습니다."; exit 1; }
          export REG_QUERY="$query"
          echo "$registry" | python3 -c "
import json, sys, os
q = os.environ.get('REG_QUERY', '').lower()
data = json.load(sys.stdin)
matches = []
for p in data.get('packs', []):
    haystack = ' '.join([
        p.get('name', ''),
        p.get('display_name', ''),
        p.get('description', ''),
        ' '.join(p.get('tags', [])),
    ]).lower()
    if q in haystack:
        matches.append(p)
print(f'\n검색 결과: {len(matches)}개\n')
for p in matches[:50]:
    name = p.get('name', '')
    dn = p.get('display_name', name)
    lng = p.get('language', 'en')
    sc = p.get('sound_count', '?')
    print(f'  {name:30s} {dn} [{lng}] ({sc}개)')
"
          exit 0 ;;
        info)
          [ -z "${1:-}" ] && { echo "사용법: cromaiping packs info <이름>"; exit 1; }
          pack_json=$(registry_lookup "$1") || { echo "❌ 팩을 찾을 수 없습니다: $1"; exit 1; }
          export PACK_JSON="$pack_json"
          python3 <<'PYEOF'
import json, os
p = json.loads(os.environ['PACK_JSON'])
print(f"\n📦 {p.get('display_name', p.get('name'))}")
print(f"   ID:      {p.get('name')}")
print(f"   설명:    {p.get('description', '-')}")
print(f"   언어:    {p.get('language', 'en')}")
print(f"   사운드:  {p.get('sound_count', '?')}개")
sz = p.get('total_size_bytes', 0)
if sz:
    if sz < 1024*1024:
        print(f"   크기:    {sz//1024} KB")
    else:
        print(f"   크기:    {sz/(1024*1024):.1f} MB")
cats = p.get('categories', [])
if cats:
    print(f"   카테고리: {', '.join(cats)}")
tags = p.get('tags', [])
if tags:
    print(f"   태그:    {', '.join(tags)}")
print(f"   라이선스: {p.get('license', '?')}")
print(f"\n💡 설치: cromaiping packs install {p.get('name')}")
PYEOF
          exit 0 ;;
        install)
          [ -z "${1:-}" ] && { echo "사용법: cromaiping packs install <이름1>[,<이름2>,...] | --all | <URL>"; exit 1; }
          # --all 처리
          if [ "$1" = "--all" ]; then
            echo "🌐 크로마이핑 레지스트리에서 모든 팩 다운로드 중..."
            registry=$(fetch_registry) || { echo "❌ 레지스트리에 연결할 수 없습니다."; exit 1; }
            packs_to_install=$(echo "$registry" | python3 -c "
import json, sys
print(','.join(p['name'] for p in json.load(sys.stdin).get('packs', [])))
")
            set -- "$packs_to_install"
          fi

          # URL 직접 설치 처리
          if echo "$1" | grep -qE '^https?://'; then
            echo "🌐 URL에서 다운로드 중: $1"
            url="$1"
            tmp_dir=$(mktemp -d)
            if [[ "$url" == *github.com/* ]] && [[ "$url" != *archive* ]]; then
              # GitHub 레포 URL → archive URL로 변환
              repo=$(echo "$url" | sed -E 's|https?://github.com/([^/]+/[^/]+).*|\1|')
              url="https://github.com/$repo/archive/HEAD.tar.gz"
            fi
            if curl -fsSL --max-time 60 "$url" -o "$tmp_dir/pack.tar.gz" && \
               tar -xzf "$tmp_dir/pack.tar.gz" -C "$tmp_dir"; then
              manifest=$(find "$tmp_dir" -name "openpeon.json" -type f 2>/dev/null | head -1)
              if [ -n "$manifest" ]; then
                pack_name=$(python3 -c "import json; print(json.load(open('$manifest'))['name'])")
                pack_src=$(dirname "$manifest")
                rm -rf "$CROMAIPING_DIR/packs/$pack_name"
                mkdir -p "$CROMAIPING_DIR/packs/$pack_name"
                cp -r "$pack_src/." "$CROMAIPING_DIR/packs/$pack_name/"
                echo "✅ $pack_name 설치 완료"
              else
                echo "❌ 매니페스트 없음" >&2
              fi
            else
              echo "❌ 다운로드 실패" >&2
            fi
            rm -rf "$tmp_dir"
            exit 0
          fi

          # 콤마 구분 다중 설치
          IFS=',' read -ra pack_names <<< "$1"
          total=${#pack_names[@]}
          success=0
          failed=0
          echo "🌐 크로마이핑 레지스트리에서 ${total}개 팩 설치 중..."
          for pack_name in "${pack_names[@]}"; do
            pack_name=$(echo "$pack_name" | xargs)  # trim
            [ -z "$pack_name" ] && continue
            echo ""
            echo "📦 $pack_name"
            pack_json=$(registry_lookup "$pack_name")
            if [ -z "$pack_json" ]; then
              echo "  ❌ 레지스트리에서 찾을 수 없음" >&2
              failed=$((failed + 1))
              continue
            fi
            if download_pack "$pack_json"; then
              echo "  ✅ 설치 완료"
              success=$((success + 1))
            else
              failed=$((failed + 1))
            fi
          done
          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "✅ 성공: ${success}개  ❌ 실패: ${failed}개"
          exit 0 ;;
        remove|rm|uninstall)
          [ -z "${1:-}" ] && { echo "사용법: cromaiping packs remove <이름>"; exit 1; }
          if [ "$1" = "--all-but-active" ]; then
            active_pack=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['default_pack'])")
            removed=0
            for p in "$CROMAIPING_DIR/packs/"*/; do
              [ -d "$p" ] || continue
              name=$(basename "$p")
              if [ "$name" != "$active_pack" ]; then
                rm -rf "$p"
                removed=$((removed + 1))
              fi
            done
            echo "✅ ${removed}개 팩 제거됨 (활성 팩 '$active_pack' 제외)"
          else
            IFS=',' read -ra pack_names <<< "$1"
            for pack_name in "${pack_names[@]}"; do
              pack_name=$(echo "$pack_name" | xargs)
              if [ -d "$CROMAIPING_DIR/packs/$pack_name" ]; then
                rm -rf "$CROMAIPING_DIR/packs/$pack_name"
                echo "✅ $pack_name 제거됨"
              else
                echo "⚠️  $pack_name 설치되어 있지 않음"
              fi
            done
          fi
          exit 0 ;;
        update)
          # 모든 설치된 팩 다시 다운로드
          if [ -z "${1:-}" ]; then
            echo "🔄 모든 팩 업데이트 중..."
            for p in "$CROMAIPING_DIR/packs/"*/; do
              [ -d "$p" ] || continue
              name=$(basename "$p")
              echo ""
              echo "📦 $name"
              pack_json=$(registry_lookup "$name")
              if [ -n "$pack_json" ]; then
                if download_pack "$pack_json"; then
                  echo "  ✅ 업데이트 완료"
                fi
              else
                echo "  ⚠️  레지스트리에서 찾을 수 없음 (스킵)"
              fi
            done
          else
            pack_json=$(registry_lookup "$1") || { echo "❌ 레지스트리에서 찾을 수 없음"; exit 1; }
            echo "📦 $1 업데이트 중..."
            download_pack "$pack_json" && echo "✅ 업데이트 완료"
          fi
          exit 0 ;;
        use)
          [ -z "${1:-}" ] && { echo "사용법: cromaiping packs use <이름>"; exit 1; }
          if [ ! -d "$CROMAIPING_DIR/packs/$1" ]; then
            echo "⚠️  '$1' 이 설치되어 있지 않습니다. 자동 설치 시도..."
            pack_json=$(registry_lookup "$1") || { echo "❌ 레지스트리에서 찾을 수 없음"; exit 1; }
            download_pack "$pack_json" || exit 1
          fi
          python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['default_pack'] = '$1'
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('🎵 기본 팩이 변경됨: $1')
"
          exit 0 ;;
        next)
          # 다음 팩으로 순환
          installed=()
          for p in "$CROMAIPING_DIR/packs/"*/; do
            [ -d "$p" ] && installed+=("$(basename "$p")")
          done
          [ ${#installed[@]} -lt 2 ] && { echo "팩이 1개 이하입니다. 더 설치해주세요."; exit 0; }
          current=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['default_pack'])")
          next_idx=0
          for i in "${!installed[@]}"; do
            if [ "${installed[$i]}" = "$current" ]; then
              next_idx=$(( (i + 1) % ${#installed[@]} ))
              break
            fi
          done
          next_pack="${installed[$next_idx]}"
          python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
cfg['default_pack'] = '$next_pack'
json.dump(cfg, open('$CONFIG_FILE','w'), ensure_ascii=False, indent=2)
print('🎵 팩 변경됨: $next_pack')
"
          exit 0 ;;
        *)
          cat <<EOF
사용법: cromaiping packs <서브명령어>

서브명령어:
  list                    설치된 팩 목록
  list --registry         레지스트리에서 사용 가능한 팩 목록
  list --registry --lang=ko   한국어 팩만 보기
  search <키워드>         팩 검색 (한글 키워드 OK)
  info <이름>             팩 상세 정보
  install <이름>          팩 설치 (콤마로 여러 개)
  install <URL>           URL에서 직접 설치
  install --all           모든 팩 설치
  remove <이름>           팩 제거
  remove --all-but-active 활성 팩 제외하고 모두 제거
  update [이름]           팩 업데이트 (인자 없으면 전체)
  use <이름>              팩 변경 (없으면 자동 설치)
  next                    다음 팩으로 순환
EOF
          exit 0 ;;
      esac
      ;;
    preview)
      shift
      cat="${1:-session.start}"
      pack=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['default_pack'])")
      manifest="$CROMAIPING_DIR/packs/$pack/openpeon.json"
      [ -f "$manifest" ] || { echo "매니페스트 없음: $manifest"; exit 1; }
      file=$(python3 -c "
import json, random
m = json.load(open('$manifest'))
sounds = m.get('categories', {}).get('$cat', {}).get('sounds', [])
if sounds:
    print('$CROMAIPING_DIR/packs/$pack/' + random.choice(sounds)['file'])
")
      [ -n "$file" ] && [ -f "$file" ] && play_sound "$file" "0.5" && echo "재생: $cat" || echo "사운드 없음: $cat"
      exit 0 ;;
    help|--help|-h|*)
      cat <<EOF
크로마이핑 v$VERSION — AI 코딩 도구용 한국형 사운드 알림

사용법: cromaiping <명령어> [인자]

기본 명령어:
  status                현재 상태 확인
  toggle                음소거 토글
  pause / mute          음소거
  resume / unmute       활성화
  volume [0-100]        볼륨 조회/설정
  use <팩이름>          기본 팩 변경
  list                  설치된 팩 목록
  preview [카테고리]    카테고리 사운드 미리듣기

팩 관리:
  packs list [--registry]    팩 목록 (설치본 또는 레지스트리)
  packs search <키워드>      팩 검색
  packs info <이름>          팩 상세 정보
  packs install <이름>       팩 설치
  packs remove <이름>        팩 제거
  packs update [이름]        팩 업데이트
  packs use <이름>           팩 변경 (자동 설치 포함)
  packs next                 다음 팩으로 순환

기타:
  version               버전 정보
  help                  이 도움말

설정 파일: $CONFIG_FILE
홈페이지: https://cromaizing.com/cromaiping
EOF
      exit 0 ;;
  esac
fi

# ─────────────────────────────────────────────
# 훅 모드: stdin으로 JSON 이벤트 수신
# ─────────────────────────────────────────────
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Python으로 이벤트 처리 (bash로 JSON 다루기 어려움)
RESULT=$(python3 <<PYEOF
import json, os, sys, random, time

CONFIG_FILE = "$CONFIG_FILE"
STATE_FILE = "$STATE_FILE"
CROMAIPING_DIR = "$CROMAIPING_DIR"

# 이벤트 파싱
try:
    event_data = json.loads(r'''$INPUT''')
except Exception as e:
    sys.exit(0)

# Cursor lowercaseEvent → PascalCase 변환
CURSOR_MAP = {
    'sessionStart': 'SessionStart', 'sessionEnd': 'SessionEnd',
    'beforeSubmitPrompt': 'UserPromptSubmit', 'stop': 'Stop',
    'preToolUse': 'UserPromptSubmit', 'postToolUse': 'Stop',
}
raw_event = event_data.get('hook_event_name', '')
event = CURSOR_MAP.get(raw_event, raw_event)

session_id = event_data.get('session_id') or event_data.get('conversation_id') or 'default'

# 설정 로드
try:
    cfg = json.load(open(CONFIG_FILE))
except Exception:
    cfg = {}

if not cfg.get('enabled', True):
    sys.exit(0)

# 카테고리 토글 확인
cats_enabled = cfg.get('categories', {})

# 상태 로드
try:
    state = json.load(open(STATE_FILE))
except Exception:
    state = {}

# 이벤트 → 카테고리 매핑
EVENT_MAP = {
    'SessionStart': 'session.start',
    'UserPromptSubmit': 'task.acknowledge',
    'Stop': 'task.complete',
    'SubagentStop': 'task.complete',
    'PermissionRequest': 'input.required',
    'PostToolUseFailure': 'task.error',
    'PreCompact': 'resource.limit',
}
category = EVENT_MAP.get(event)

# 특수 처리: SessionStart의 source=compact는 무시
if event == 'SessionStart' and event_data.get('source') == 'compact':
    sys.exit(0)

# 특수 처리: UserPromptSubmit 빠른 입력 → user.spam 감지
if event == 'UserPromptSubmit' and cats_enabled.get('user.spam', True):
    threshold = cfg.get('annoyed_threshold', 3)
    window = cfg.get('annoyed_window_seconds', 10)
    now = time.time()
    timestamps = state.get('prompt_timestamps', {})
    ts = [t for t in timestamps.get(session_id, []) if now - t < window]
    ts.append(now)
    timestamps[session_id] = ts
    state['prompt_timestamps'] = timestamps
    if len(ts) >= threshold:
        category = 'user.spam'

# 특수 처리: PostToolUseFailure는 Bash 도구 실패만
if event == 'PostToolUseFailure':
    if event_data.get('tool_name') != 'Bash':
        sys.exit(0)

# Subagent suppress 옵션
if event == 'SubagentStop' and cfg.get('suppress_subagent_complete', False):
    sys.exit(0)

if not category:
    json.dump(state, open(STATE_FILE, 'w'))
    sys.exit(0)

# 카테고리 비활성화 확인
if not cats_enabled.get(category, True):
    json.dump(state, open(STATE_FILE, 'w'))
    sys.exit(0)

# 활성 팩 결정 (path_rules > default_pack)
pack = cfg.get('default_pack', 'cromaiping_default')
cwd = event_data.get('cwd', '') or os.getcwd()

# path_rules 적용
import fnmatch
for rule in cfg.get('path_rules', []):
    if fnmatch.fnmatch(cwd, rule.get('pattern', '')):
        pack = rule.get('pack', pack)
        break

# 매니페스트 로드
manifest_path = os.path.join(CROMAIPING_DIR, 'packs', pack, 'openpeon.json')
if not os.path.exists(manifest_path):
    sys.exit(0)
try:
    manifest = json.load(open(manifest_path))
except Exception:
    sys.exit(0)

# 카테고리에서 사운드 선택
sounds = manifest.get('categories', {}).get(category, {}).get('sounds', [])
if not sounds:
    # category_aliases 확인
    for alias, cesp in manifest.get('category_aliases', {}).items():
        if cesp == category:
            sounds = manifest.get('categories', {}).get(alias, {}).get('sounds', [])
            if sounds:
                break

if not sounds:
    sys.exit(0)

# 직전 사운드 회피
last_played = state.get('last_played', {}).get(category, '')
candidates = [s for s in sounds if s.get('file') != last_played] or sounds
chosen = random.choice(candidates)
file_path = os.path.join(CROMAIPING_DIR, 'packs', pack, chosen['file'])

# 상태 업데이트
state.setdefault('last_played', {})[category] = chosen.get('file', '')
state['last_event'] = {'event': event, 'category': category, 'pack': pack, 'time': time.time()}
try:
    json.dump(state, open(STATE_FILE, 'w'))
except Exception:
    pass

# 출력 (bash가 받아서 재생)
volume = cfg.get('volume', 0.5)
notify_msg = chosen.get('label', '')
print(f"PLAY={file_path}")
print(f"VOL={volume}")
print(f"LABEL={notify_msg}")
print(f"NOTIFY={'1' if cfg.get('desktop_notifications', True) else '0'}")
print(f"ACTIVE_PACK={pack}")
PYEOF
)

# Python 결과 파싱
PLAY_FILE=""
VOL="0.5"
LABEL=""
NOTIFY="0"
ACTIVE_PACK=""
while IFS='=' read -r key val; do
  case "$key" in
    PLAY) PLAY_FILE="$val" ;;
    VOL) VOL="$val" ;;
    LABEL) LABEL="$val" ;;
    NOTIFY) NOTIFY="$val" ;;
    ACTIVE_PACK) ACTIVE_PACK="$val" ;;
  esac
done <<< "$RESULT"

# 사운드 재생
[ -n "$PLAY_FILE" ] && [ -f "$PLAY_FILE" ] && play_sound "$PLAY_FILE" "$VOL"

# 데스크톱 알림 (옵션) — 매니페스트 overlay 정보로 GIF 오버레이 렌더링
[ "$NOTIFY" = "1" ] && [ -n "$LABEL" ] && notify "$LABEL" "크로마이핑" "$ACTIVE_PACK"

exit 0
