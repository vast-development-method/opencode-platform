#!/usr/bin/env bash
set -Eeuo pipefail

OUTPUT="${1:-/tmp/vdm-voice-$$.wav}"
DURATION="${VDM_VOICE_DURATION:-0}"
: "${VDM_STT_URL:?Set VDM_STT_URL to an OpenAI-compatible /v1/audio/transcriptions endpoint}"
VDM_STT_MODEL="${VDM_STT_MODEL:-whisper-1}"

cleanup() {
    rm -f "$OUTPUT"
}
trap cleanup EXIT

command -v arecord >/dev/null 2>&1 || {
    printf 'Install alsa-utils for arecord.\n' >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || {
    printf 'jq is required.\n' >&2
    exit 1
}

if [ "$DURATION" -gt 0 ] 2>/dev/null; then
    printf 'Recording for %s seconds.\n' "$DURATION" >&2
    arecord -q -f S16_LE -r 16000 -c 1 -d "$DURATION" "$OUTPUT"
else
    printf 'Recording. Press Enter to stop.\n' >&2
    arecord -q -f S16_LE -r 16000 -c 1 "$OUTPUT" &
    recorder_pid=$!
    read -r _
    kill -INT "$recorder_pid" >/dev/null 2>&1 || true
    wait "$recorder_pid" || {
        status=$?
        [ "$status" -eq 130 ] || exit "$status"
    }
fi

declare -a AUTH_HEADER
if [ -n "${VDM_STT_TOKEN:-}" ]; then
    AUTH_HEADER=(-H "Authorization: Bearer ${VDM_STT_TOKEN}")
fi

response="$(
    curl --fail-with-body -sS \
        "${AUTH_HEADER[@]}" \
        -F "file=@${OUTPUT}" \
        -F "model=${VDM_STT_MODEL}" \
        "$VDM_STT_URL"
)"

text="$(jq -r '.text // empty' <<<"$response")"
[ -n "$text" ] || {
    printf '%s\n' "$response" >&2
    exit 1
}

printf '%s\n' "$text"
if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy
    printf 'Transcription copied to the Wayland clipboard.\n' >&2
fi
