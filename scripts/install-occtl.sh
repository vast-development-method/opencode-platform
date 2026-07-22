#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${HOME}/.local/bin/occtl"
install -d -m 0755 "$(dirname "$TARGET")"
cat > "$TARGET" <<EOF
#!/usr/bin/env bash
exec "$ROOT_DIR/scripts/occtl.sh" "\$@"
EOF
chmod 0755 "$TARGET"
printf 'Installed %s\n' "$TARGET"
