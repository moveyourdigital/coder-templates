#!/usr/bin/env bash
# Scan an image for fixable CRITICAL vulnerabilities with trivy.
#
#   scripts/trivy-scan.sh <image>          table; exit 1 if any are found
#   scripts/trivy-scan.sh <image> --json   JSON on stdout; exit 0 (count with jq)
#
# The image is pinned by digest (Renovate updates tag and digest).
set -euo pipefail

img="${1:?image}"
trivy_image="aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa"
out=(--exit-code 1)
if [ "${2:-}" = --json ]; then
  out=(--format json --exit-code 0)
fi

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$trivy_image" image \
  --scanners vuln --severity CRITICAL --ignore-unfixed --no-progress \
  "${out[@]}" "$img"
