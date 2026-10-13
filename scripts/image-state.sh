#!/usr/bin/env bash
# Print the state of an image tag in the registry: "present" or "absent".
# Any other result (network, 401, rate limit, ...) prints an error and exits
# 2. Callers must fail then (fail closed), not treat the tag as absent.
#
# GHCR answers "denied" both for a package that does not exist yet (new
# template) and for one the token cannot read. Both count as absent: a token
# that cannot read a package cannot push to it, so no tag is overwritten.
#
#   scripts/image-state.sh <image>
set -euo pipefail

img="${1:?image}"
if out="$(docker manifest inspect "$img" 2>&1)"; then
  echo present
  exit 0
fi
case "$out" in
  *"manifest unknown"* | *": denied"*) echo absent ;;
  *)
    echo "error: cannot check $img: $(printf '%s' "$out" | sed -n 1p)" >&2
    exit 2
    ;;
esac
