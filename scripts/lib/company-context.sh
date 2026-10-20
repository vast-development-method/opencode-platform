#!/usr/bin/env bash

validate_company_context() {
    local instance="${1:?instance required}"
    # Older standalone images have no context facility. Configured/new images
    # verify ownership, every checksum and the actual OpenCode instruction list.
    if project_cmd exec "$instance" --mode=non-interactive -- \
        test -f /usr/local/libexec/vdm-company-context.py; then
        project_cmd exec "$instance" --mode=non-interactive -- \
            python3 /usr/local/libexec/vdm-company-context.py verify \
            "$AGENT_HOME/.config/opencode/opencode.json" >/dev/null ||
            die "Company instructions or provenance changed; run company-sync again"
    fi
}
