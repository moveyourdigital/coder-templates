#!/usr/bin/env bash
# Build, scan and smoke-test the workspace images; push with --push.
# Same steps as .github/workflows/build-images.yml, for OneDev CI.
# A tag that already exists in the registry is skipped (tags are immutable),
# after a check that it was built from the same build/.
#
#   scripts/ci-images.sh [--push]
#
# Env: COMMIT (revision label, default HEAD), SOURCE_URL (source label).
set -euo pipefail

push=false
if [ "${1:-}" = --push ]; then push=true; fi
rev="${COMMIT:-$(git rev-parse HEAD)}"

for t in node-js php-wordpress ops; do
  img="$(scripts/image-ref.sh "$t/main.tf")"
  echo "== $t: $img"

  # Fails (exit 2) on registry errors: never build/push on a guess.
  state="$(scripts/image-state.sh "$img")"
  if [ "$state" = present ]; then
    built_from="$(scripts/image-revision.sh "$img")"
    if ! git cat-file -e "$built_from^{commit}" 2>/dev/null \
      || ! git diff --quiet "$built_from" HEAD -- "$t/build"; then
      echo "error: $img exists but was built from a different $t/build/ (${built_from:0:7}). Use a new tag." >&2
      exit 1
    fi
    echo "Tag exists (same build/), nothing to build."
    continue
  fi

  docker buildx build --load --pull --platform linux/amd64 \
    --label "org.opencontainers.image.revision=$rev" \
    --label "org.opencontainers.image.source=${SOURCE_URL:-}" \
    --label "org.opencontainers.image.title=coder-workspace-$t" \
    -t "$img" "$t/build"
  scripts/trivy-scan.sh "$img"
  tests/smoke.sh "$t" "$img"
  if $push; then
    docker push "$img"
  else
    echo "Built, scanned and smoke-tested (no push)."
  fi
done
