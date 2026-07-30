#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE_NAME"
project_cmd info "$NAME" >/dev/null 2>&1 || die "Unknown instance: $NAME"

agents=(orchestrator architect implementer tester reviewer security browser-qa documenter php-joomla python cpp typescript)
for agent in "${agents[@]}"; do
    read -r -p "Model for ${agent} (provider/model, empty to inherit): " model
    if [ -n "$model" ] && [[ ! "$model" =~ ^[A-Za-z0-9._:/+-]+$ ]]; then
        die "Invalid model identifier: $model"
    fi

    # The single-quoted program is evaluated inside the guest, where the injected variables exist.
    # shellcheck disable=SC2016
    project_cmd exec "$NAME" \
        --env "AGENT_NAME=$agent" \
        --env "AGENT_MODEL=$model" \
        --env "AGENT_HOME=$AGENT_HOME" \
        -- bash -c '
set -Eeuo pipefail
: "${AGENT_HOME:?agent home is required}"
file="$AGENT_HOME/.config/opencode/agents/${AGENT_NAME}.md"
if grep -q "^model:" "$file"; then
    if [ -n "$AGENT_MODEL" ]; then
        sed -i "s|^model:.*|model: ${AGENT_MODEL}|" "$file"
    else
        sed -i "/^model:/d" "$file"
    fi
elif [ -n "$AGENT_MODEL" ]; then
    sed -i "/^mode:/a model: ${AGENT_MODEL}" "$file"
fi
'
done
