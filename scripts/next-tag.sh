#!/usr/bin/env bash
# Print the image with the next free patch tag, e.g.
#   ghcr.io/...:v0.6.0 -> ghcr.io/...:v0.6.1
# Tags that already exist in the registry are skipped (tags are immutable).
#
#   scripts/next-tag.sh <image>
set -euo pipefail

img="${1:?image}"
repo="${img%:*}"
tag="${img##*:}"
if [[ ! "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "error: tag is not vMAJOR.MINOR.PATCH: $tag" >&2
  exit 1
fi
major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"

for _ in $(seq 1 20); do
  patch=$((patch + 1))
  next="$repo:v$major.$minor.$patch"
  if [ "$("$(dirname "$0")/image-state.sh" "$next")" = absent ]; then
    echo "$next"
    exit 0
  fi
done
echo "error: no free patch tag after $tag" >&2
exit 1
