#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

command="${1:-help}"
shift || true

case "$command" in
    bootstrap) exec "$SCRIPT_DIR/bootstrap-host.sh" "$@" ;;
    apply) exec "$SCRIPT_DIR/apply-incus.sh" "$@" ;;
    build) exec "$SCRIPT_DIR/build-image.sh" "$@" ;;
    build-all) exec "$SCRIPT_DIR/build-all-images.sh" "$@" ;;
    launch) exec "$SCRIPT_DIR/launch-vm.sh" "$@" ;;
    session) exec "$SCRIPT_DIR/start-session.sh" "$@" ;;
    stop-session) exec "$SCRIPT_DIR/stop-session.sh" "$@" ;;
    runtime-env) exec "$SCRIPT_DIR/create-runtime-env.sh" "$@" ;;
    mcp) exec "$SCRIPT_DIR/mcp-toggle.sh" "$@" ;;
    models) exec "$SCRIPT_DIR/configure-models.sh" "$@" ;;
    package) exec "$SCRIPT_DIR/package-image.sh" "$@" ;;
    import-package) exec "$SCRIPT_DIR/import-image-package.sh" "$@" ;;
    publish-package) exec "$SCRIPT_DIR/publish-gitea-package.sh" "$@" ;;
    export) exec "$SCRIPT_DIR/export-instance.sh" "$@" ;;
    import) exec "$SCRIPT_DIR/import-instance.sh" "$@" ;;
    voice) exec "$SCRIPT_DIR/voice-transcribe.sh" "$@" ;;
    help|-h|--help)
        cat <<'EOF'
occtl commands:
  bootstrap
  apply
  build VARIANT
  build-all
  launch VARIANT INSTANCE
  runtime-env INSTANCE
  session INSTANCE [RUNTIME_ENV_FILE]
  stop-session INSTANCE
  mcp INSTANCE SERVER true|false
  models INSTANCE
  package VARIANT
  import-package DIRECTORY [IMAGE_ALIAS]
  publish-package VARIANT
  export INSTANCE [FILE]
  import FILE INSTANCE
  voice [TEMP_WAV]
EOF
        ;;
    *) printf 'Unknown command: %s\n' "$command" >&2; exit 1 ;;
esac
