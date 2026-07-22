#!/usr/bin/env bash
set -Eeuo pipefail
PACKAGE_DIR="${1:?package directory required}"

subjects="$(
    jq '[.payload[] | {name:.name,digest:{sha256:.sha256}}]' "$PACKAGE_DIR/manifest.json"
)"
jq -n \
    --argjson subject "$subjects" \
    --arg revision "$(jq -r '.source_revision' "$PACKAGE_DIR/manifest.json")" \
    --arg started "$(jq -r '.packaged_at' "$PACKAGE_DIR/manifest.json")" \
    --arg builder "${VDM_BUILDER_ID:-https://platform.vdm.dev/builders/incus/unregistered}" \
    '{
      _type:"https://in-toto.io/Statement/v1",
      subject:$subject,
      predicateType:"https://slsa.dev/provenance/v1",
      predicate:{
        buildDefinition:{
          buildType:"https://platform.vdm.dev/build-types/incus-image/v1",
          externalParameters:{},
          internalParameters:{},
          resolvedDependencies:[{
            uri:"git+https://github.com/vast-development-method/opencode-platform",
            digest:{gitCommit:$revision}
          }]
        },
        runDetails:{
          builder:{id:$builder},
          metadata:{invocationId:env.GITHUB_RUN_ID,startedOn:$started,finishedOn:(now | todateiso8601)}
        }
      }
    }' > "$PACKAGE_DIR/provenance.intoto.json"
