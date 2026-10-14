#!/usr/bin/env bash
# Print the Git commit an image was built from (OCI label
# org.opencontainers.image.revision, set by the workflows). Fails if missing.
#
#   scripts/image-revision.sh <image>
set -euo pipefail

img="${1:?image}"
rev="$(docker buildx imagetools inspect "$img" \
  --format '{{ index .Image.Config.Labels "org.opencontainers.image.revision" }}')"
if [[ ! "$rev" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: no revision label on $img" >&2
  exit 1
fi
echo "$rev"
