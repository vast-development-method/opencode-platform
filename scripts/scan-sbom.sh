#!/usr/bin/env bash
set -Eeuo pipefail
PACKAGE_DIR="${1:?package directory required}"
command -v grype >/dev/null 2>&1 || { printf 'grype is required\n' >&2; exit 1; }
grype "sbom:$PACKAGE_DIR/sbom.spdx.json" --output json > "$PACKAGE_DIR/vulnerabilities.grype.json"
jq -e '.matches | type == "array"' "$PACKAGE_DIR/vulnerabilities.grype.json" >/dev/null

critical="$(jq '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "$PACKAGE_DIR/vulnerabilities.grype.json")"
high_fixed="$(jq '[.matches[] | select(.vulnerability.severity == "High" and ((.vulnerability.fix.versions // []) | length > 0))] | length' "$PACKAGE_DIR/vulnerabilities.grype.json")"
jq -n \
    --argjson critical "$critical" \
    --argjson high_with_fix "$high_fixed" \
    --arg result "$([ "$critical" -eq 0 ] && [ "$high_fixed" -eq 0 ] && printf pass || printf fail)" \
    '{policy:"security/vulnerability-policy.yaml",critical:$critical,high_with_fix:$high_with_fix,result:$result}' \
    > "$PACKAGE_DIR/evidence/vulnerability-policy-result.json"
[ "$critical" -eq 0 ] && [ "$high_fixed" -eq 0 ] || {
    printf 'Vulnerability policy failed: critical=%s high-with-fix=%s\n' "$critical" "$high_fixed" >&2
    exit 1
}
