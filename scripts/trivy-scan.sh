#!/usr/bin/env bash
# Scan an image for fixable vulnerabilities with trivy.
#
#   scripts/trivy-scan.sh <image>          CRITICAL, table; exit 1 if any found
#   scripts/trivy-scan.sh <image> --json   CRITICAL, JSON on stdout; exit 0
#   scripts/trivy-scan.sh <image> --sarif  HIGH + CRITICAL, SARIF on stdout;
#                                          exit 0 (GitHub Security tab)
#
# The image is pinned by digest (Renovate updates tag and digest).
set -euo pipefail

img="${1:?image}"
trivy_image="aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa"
severity=CRITICAL
case "${2:-}" in
  "") out=(--exit-code 1) ;;
  --json) out=(--format json --exit-code 0) ;;
  --sarif) severity=HIGH,CRITICAL out=(--format sarif --exit-code 0) ;;
  *) echo "usage: $0 <image> [--json|--sarif]" >&2; exit 2 ;;
esac

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$trivy_image" image \
  --scanners vuln --severity "$severity" --ignore-unfixed --no-progress \
  "${out[@]}" "$img"
