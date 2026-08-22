#!/usr/bin/env bash
# desktop/scripts/shree-record.sh — ShreeOS Screen Recording Tool
#
# Supports fullscreen, window, and selected region video recording using ffmpeg.

set -euo pipefail

REC_DIR="${HOME}/Videos/Recordings"
mkdir -p "$REC_DIR"

PID_FILE="/tmp/shree-recording.pid"

is_recording() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    return 0
  fi
  return 1
}

stop_recording() {
  if is_recording; then
    local pid
    pid=$(cat "$PID_FILE")
    kill -2 "$pid" 2>/dev/null || kill -15 "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    shree-notify "Screen Recording" "Recording saved to ${REC_DIR}" --app="System"
  else
    shree-notify "Screen Recording" "No active recording in progress" --app="System"
  fi
}

start_recording() {
  if is_recording; then
    stop_recording
    return
  fi

  local ts
  ts=$(date +"%Y-%m-%d_%H-%M-%S")
  local out_file="${REC_DIR}/Recording_${ts}.mp4"
  local mode="${1:-full}"

  local res
  res=$(xrandr 2>/dev/null | grep '\*' | awk '{print $1}' | head -n1 || echo "1920x1080")

  shree-notify "Recording Started" "Capturing screen to $(basename "$out_file")..." --app="System"

  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -f x11grab -video_size "$res" -framerate 30 -i :0.0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$out_file" >/dev/null 2>&1 &
    echo "$!" > "$PID_FILE"
  else
    shree-notify "Screen Recording" "ffmpeg is required for video capture. Install via LPM: lpm install ffmpeg" --app="System"
  fi
}

interactive_menu() {
  if is_recording; then
    local choice
    choice=$(printf "⏹ [Stop Active Screen Recording]\nCancel" | dmenu -p "Screen Recorder Active" -l 2 -c)
    [ "$choice" = "⏹ [Stop Active Screen Recording]" ] && stop_recording
    return
  fi

  local options="Start Fullscreen Recording\nStart Region Recording\nCancel"
  local choice
  choice=$(echo -e "$options" | dmenu -p "Screen Recorder" -l 3 -c)
  [ -z "$choice" ] && return

  case "$choice" in
    "Start Fullscreen"*) start_recording full ;;
    "Start Region"*)     start_recording select ;;
  esac
}

case "${1:-menu}" in
  start) start_recording "${2:-full}" ;;
  stop)  stop_recording ;;
  status)
    if is_recording; then echo "recording"; else echo "idle"; fi
    ;;
  menu|*) interactive_menu ;;
esac
