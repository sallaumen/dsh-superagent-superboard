#!/bin/sh
# Test the board's ElevenLabs voice from the terminal: no key here, the
# running board holds it. Usage:
#
#   scripts/voice.sh status
#   scripts/voice.sh say "Boa noite, o board está calmo." [--voice <id>] [--play]
#   scripts/voice.sh transcribe <file> [--language pt]
#
# The board URL comes from VOICE_URL (default: the dev server).
set -eu

URL="${VOICE_URL:-http://127.0.0.1:4000/api/voice}"
OUT="${TMPDIR:-/tmp}/agent-board-voice.mp3"

command="$1"
shift || true

status() {
  curl -s "$URL/status" | python3 -m json.tool
}

say() {
  text="$1"
  shift

  voice=""
  play=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --voice)
        voice="$2"
        shift 2
        ;;
      --play)
        play=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  query="text=$(printf '%s' "$text" | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read()))')"
  [ -z "$voice" ] || query="$query&voice=$voice"

  status_code=$(curl -s -o "$OUT" -w "%{http_code}" "$URL/speech?$query")
  if [ "$status_code" != "200" ]; then
    cat "$OUT"
    echo
    exit 1
  fi

  echo "saved $OUT"
  if [ -n "$play" ] && command -v afplay >/dev/null 2>&1; then
    afplay "$OUT"
  fi
}

transcribe() {
  file="$1"
  shift

  language=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --language)
        language="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  query=""
  [ -z "$language" ] || query="?language=$language"

  curl -s -X POST --data-binary "@$file" \
    -H "content-type: application/octet-stream" \
    "$URL/transcribe$query" | python3 -m json.tool
}

case "$command" in
  status) status ;;
  say) say "$@" ;;
  transcribe) transcribe "$@" ;;
  *)
    echo "usage: scripts/voice.sh status|say <text> [--voice id] [--play]|transcribe <file> [--language pt]"
    exit 1
    ;;
esac
