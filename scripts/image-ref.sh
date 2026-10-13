#!/usr/bin/env bash
# Print the image reference in a main.tf (docker_image.workspace.name).
# The whole quoted value must be a valid reference: a value with shell
# syntax (e.g. "$()") does not match, so it never reaches a shell.
#
#   scripts/image-ref.sh <template>/main.tf    (or - for stdin)
set -euo pipefail

f="${1:?main.tf path or -}"
ref="$(grep -oE '"ghcr\.io/moveyourdigital/coder-workspace-[a-z-]+:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}"' "$f" \
  | sed -n 1p | tr -d '"' || true)"
if [ -z "$ref" ]; then
  echo "error: no valid ghcr.io image reference in $f" >&2
  exit 1
fi
echo "$ref"
