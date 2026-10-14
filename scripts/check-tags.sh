#!/usr/bin/env bash
# A change under <template>/build/ needs a new image tag. A tag already in
# the registry is accepted only if it was built from the same build/ (and its
# image is trivy-clean). Used by `just check-tags` and by CI.
#
#   scripts/check-tags.sh <base commit>
set -euo pipefail

base="${1:?base commit}"
err() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error file=$1::$2"; else echo "error: $2" >&2; fi; }
fail=0
for t in node-js php-wordpress ops; do
  new="$(scripts/image-ref.sh "$t/main.tf")"
  old="$(git show "$base:$t/main.tf" 2>/dev/null | scripts/image-ref.sh - 2>/dev/null || true)"
  if [ "$new" = "$old" ]; then
    if git diff --quiet "$base...HEAD" -- "$t/build"; then
      echo "ok: $t (unchanged: $new)"
    else
      err "$t/main.tf" "$t/build changed, but the image tag did not: $new"; fail=1
    fi
  else
    # Fail closed: only an explicit "absent" counts as a new tag.
    state="$(scripts/image-state.sh "$new")" || { err "$t/main.tf" "cannot check $new in the registry"; fail=1; continue; }
    if [ "$state" = present ]; then
      # An existing tag is fine only if it was built from the same build/
      # (security rebuild, or a rollback). Never re-pushed.
      rev="$(scripts/image-revision.sh "$new")" || { err "$t/main.tf" "cannot read the revision of $new"; fail=1; continue; }
      if git cat-file -e "$rev^{commit}" 2>/dev/null && git diff --quiet "$rev" HEAD -- "$t/build"; then
        # The build workflow skips existing tags: scan it here, it may
        # have CVEs found after it was built.
        if docker pull -q "$new" >/dev/null && scripts/trivy-scan.sh "$new"; then
          echo "ok: $t (existing tag, same build/ as ${rev:0:7}, trivy clean: $new)"
        else
          err "$t/main.tf" "existing tag has fixable CRITICAL vulnerabilities (or the scan failed): $new"; fail=1
        fi
      else
        err "$t/main.tf" "tag already in the registry, built from a different build/ (${rev:0:7}): $new"; fail=1
      fi
    else
      echo "ok: $t (new tag: $new)"
    fi
  fi
done
exit "$fail"
