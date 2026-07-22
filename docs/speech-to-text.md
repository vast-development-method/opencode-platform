# Speech-to-text

Voice input is possible without putting microphone access inside the VM.

The preferred design is:

```text
Host microphone -> host recorder -> trusted transcription endpoint -> text -> clipboard/OpenCode
```

This preserves the VM isolation boundary and works well on Ubuntu Wayland.

## Included script

`voice-transcribe.sh` records with `arecord`, submits the WAV file to an OpenAI-compatible
`/v1/audio/transcriptions` endpoint, prints the returned text and copies it with `wl-copy` when available.

```bash
export VDM_STT_URL=https://stt.example.com/v1/audio/transcriptions
export VDM_STT_TOKEN='short-lived-token'
./scripts/voice-transcribe.sh
```

For a local Whisper service, point the URL to the trusted local endpoint. Keep audio retention disabled unless a
documented business requirement exists.

An MCP speech server is optional. For ordinary dictation, host-side transcription is simpler and safer than giving
the agent direct microphone control.
