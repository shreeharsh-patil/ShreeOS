#!/usr/bin/env bash
# desktop/scripts/shree-record.sh — ShreeOS Screen Recording Tool
set -euo pipefail

REC_DIR="${HOME}/Videos/Recordings"
mkdir -p "$REC_DIR"

STATE_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/shreeos}"
if ! mkdir -p "$STATE_DIR" 2>/dev/null || [ ! -w "$STATE_DIR" ]; then
  STATE_DIR="${HOME}/.cache/shreeos"
  mkdir -p "$STATE_DIR"
fi
STATE_FILE="${STATE_DIR}/shree-recording.state"

read_state() {
  REC_PID=""
  REC_FILE=""
  [ -f "$STATE_FILE" ] || return 1
  {
    IFS= read -r REC_PID || true
    IFS= read -r REC_FILE || true
  } < "$STATE_FILE"
  [[ "$REC_PID" =~ ^[0-9]+$ ]] || return 1
  [ -n "$REC_FILE" ] || return 1
}

is_recording() {
  if ! read_state; then
    rm -f "$STATE_FILE"
    return 1
  fi
  if ! kill -0 "$REC_PID" 2>/dev/null; then
    rm -f "$STATE_FILE"
    return 1
  fi

  # Protect against a stale state file whose PID has been reused by another
  # process before attempting to send a signal.
  if [ -r "/proc/${REC_PID}/cmdline" ]; then
    if ! tr '\0' ' ' < "/proc/${REC_PID}/cmdline" | grep -q 'ffmpeg'; then
      rm -f "$STATE_FILE"
      return 1
    fi
  fi
  return 0
}

stop_recording() {
  if ! is_recording; then
    shree-notify "Screen Recording" "No active recording in progress" --app="System"
    return 0
  fi

  local pid="$REC_PID"
  local out_file="$REC_FILE"

  if ! kill -2 "$pid" 2>/dev/null; then
    shree-notify "Screen Recording" "Unable to stop the active recording process" --app="System" --urgent
    return 1
  fi

  for _attempt in {1..20}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    if ! kill -15 "$pid" 2>/dev/null; then
      shree-notify "Screen Recording" "Unable to terminate the active recording process" --app="System" --urgent
      return 1
    fi
    for _attempt in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.25
    done
  fi

  if kill -0 "$pid" 2>/dev/null; then
    shree-notify "Screen Recording" "Recording process did not exit; state was preserved for recovery" --app="System" --urgent
    return 1
  fi

  rm -f "$STATE_FILE"

  if [ -s "$out_file" ]; then
    shree-notify "Screen Recording" "Saved to $(basename "$out_file")" --app="System"
  else
    rm -f "$out_file"
    shree-notify "Screen Recording" "Recording stopped, but no valid video was produced" --app="System" --urgent
    return 1
  fi
}

start_recording() {
  if is_recording; then
    stop_recording
    return
  fi

  if ! command -v ffmpeg >/dev/null 2>&1; then
    shree-notify "Screen Recording" "ffmpeg is required for video capture" --app="System" --urgent
    return 1
  fi

  local ts out_file disp res pid
  ts=$(date +"%Y-%m-%d_%H-%M-%S")
  out_file="${REC_DIR}/Recording_${ts}_$$.mp4"
  disp="${DISPLAY:-:0}"
  res=""

  if command -v xrandr >/dev/null 2>&1; then
    res=$(xrandr 2>/dev/null | awk '$0 ~ /\*/ {print $1; exit}' || true)
  fi
  res="${res:-1920x1080}"

  ffmpeg -y -f x11grab -video_size "$res" -framerate 30 -i "$disp" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$out_file" >/dev/null 2>&1 &
  pid=$!

  sleep 0.5
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null || true
    rm -f "$out_file"
    shree-notify "Screen Recording" "ffmpeg could not start screen capture" --app="System" --urgent
    return 1
  fi

  umask 077
  printf '%s\n%s\n' "$pid" "$out_file" > "$STATE_FILE"
  shree-notify "Recording Started" "Capturing screen to $(basename "$out_file")" --app="System"
}

interactive_menu() {
  if is_recording; then
    local choice
    choice=$(printf "Stop Active Screen Recording\nCancel" | dmenu -p "Screen Recorder Active" -l 2 -c || true)
    [ "$choice" = "Stop Active Screen Recording" ] && stop_recording
    return
  fi

  local choice
  choice=$(printf "Start Screen Recording\nCancel" | dmenu -p "Screen Recorder" -l 2 -c || true)
  [ "$choice" = "Start Screen Recording" ] && start_recording
}

case "${1:-menu}" in
  start) start_recording ;;
  stop) stop_recording ;;
  status)
    if is_recording; then echo "recording"; else echo "idle"; fi
    ;;
  menu|*) interactive_menu ;;
esac
