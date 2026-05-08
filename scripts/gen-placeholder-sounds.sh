#!/bin/bash
# 크로마이핑 기본 팩 placeholder 사운드 생성기
# macOS 시스템 사운드를 WAV로 변환해서 packs/cromaiping_default/sounds/에 복사
# 자체 사운드 제작 전까지의 임시 사운드
set -euo pipefail

INSTALL_DIR="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/cromaiping}"
SOUND_DIR="$INSTALL_DIR/packs/cromaiping_default/sounds"
mkdir -p "$SOUND_DIR"

# 이미 있으면 스킵
if [ -f "$SOUND_DIR/start.wav" ] && [ -f "$SOUND_DIR/complete.wav" ]; then
  echo "✓ Placeholder 사운드 이미 존재"
  exit 0
fi

PLATFORM="$(uname -s)"

case "$PLATFORM" in
  Darwin)
    # macOS 시스템 사운드 → WAV 변환
    if [ -d "/System/Library/Sounds" ]; then
      declare -A MAP=(
        [start]="Glass"
        [complete]="Hero"
        [error]="Basso"
        [input]="Ping"
        [limit]="Funk"
        [spam]="Sosumi"
      )
      for name in "${!MAP[@]}"; do
        src="/System/Library/Sounds/${MAP[$name]}.aiff"
        dst="$SOUND_DIR/${name}.wav"
        [ -f "$src" ] && afconvert "$src" "$dst" -d LEI16 -f WAVE 2>/dev/null && echo "  ✓ ${name}.wav"
      done
    fi ;;
  Linux)
    # Linux: 빈 (무음) WAV 파일 1초짜리 생성
    if command -v ffmpeg >/dev/null 2>&1; then
      for name in start complete error input limit spam; do
        ffmpeg -f lavfi -i anullsrc=r=22050:cl=mono -t 0.5 -c:a pcm_s16le \
          "$SOUND_DIR/${name}.wav" 2>/dev/null && echo "  ✓ ${name}.wav (silent)"
      done
    else
      echo "⚠ ffmpeg 필요 (Linux placeholder 생성용)"
    fi ;;
  *)
    echo "⚠ 이 플랫폼($PLATFORM)에서는 placeholder 자동 생성 불가"
    echo "   $SOUND_DIR/ 에 사운드를 직접 추가해주세요." ;;
esac

echo "✓ Placeholder 사운드 생성 완료: $SOUND_DIR"
