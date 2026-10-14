# Coder templates — images are built by GitHub Actions and pushed to GHCR.
#
# The image reference is in <template>/main.tf (docker_image.workspace.name).
# Patch versions (main.tf only) keep the image tag; minor/major bump it.
#
#   just lint
#   just validate                          # terraform validate each template
#   just check-tags                        # build/ changed => new image tag
#   just image node-js                     # image used by the template
#   just wait-image node-js                # wait until CI has pushed it
#   just release node-js v0.4.1 "message"  # check image, push template, git tag
#   just build-local node-js               # optional local test build
#   just smoke node-js                     # smoke test the image

templates := "node-js php-wordpress ops"

default:
    @just --list

# Check formatting, Dockerfiles, JSON, scripts, workflows, Renovate config and secrets
lint:
    terraform fmt -check -recursive
    hadolint --config .hadolint.yaml */build/Dockerfile
    for f in */build/*.json; do python3 -m json.tool "$f" >/dev/null || exit 1; done
    shellcheck tests/*.sh scripts/*.sh
    actionlint
    check-jsonschema --builtin-schema vendor.renovate renovate.json
    zizmor -q --no-progress --min-severity low .github/workflows
    gitleaks dir . --no-banner --redact

# terraform validate each template (in a temp copy: no lock file left behind)
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
    mkdir -p "$TF_PLUGIN_CACHE_DIR"
    work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
    for t in {{templates}}; do
      mkdir "$work/$t" && cp "$t"/*.tf "$work/$t"/
      terraform -chdir="$work/$t" init -backend=false -input=false >/dev/null
      terraform -chdir="$work/$t" validate -no-color >/dev/null
      echo "valid: $t"
    done

# A change under build/ needs a new image tag. A tag already in GHCR is
# accepted only if it was built from the same build/.
check-tags base="origin/main":
    #!/usr/bin/env bash
    set -euo pipefail
    err() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error file=$1::$2"; else echo "error: $2" >&2; fi; }
    fail=0
    for t in {{templates}}; do
      new="$(just image "$t")"
      old="$(git show "{{base}}:$t/main.tf" 2>/dev/null | scripts/image-ref.sh - 2>/dev/null || true)"
      if [ "$new" = "$old" ]; then
        if git diff --quiet "{{base}}...HEAD" -- "$t/build"; then
          echo "ok: $t (unchanged: $new)"
        else
          err "$t/main.tf" "$t/build changed, but the image tag did not: $new"; fail=1
        fi
      else
        # Fail closed: only an explicit "absent" counts as a new tag.
        state="$(scripts/image-state.sh "$new")" || { err "$t/main.tf" "cannot check $new in GHCR"; fail=1; continue; }
        if [ "$state" = present ]; then
          # An existing tag is fine only if it was built from the same build/
          # (security rebuild by scan.yml, or a rollback). Never re-pushed.
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
            err "$t/main.tf" "tag already in GHCR, built from a different build/ (${rev:0:7}): $new"; fail=1
          fi
        else
          echo "ok: $t (new tag: $new)"
        fi
      fi
    done
    exit "$fail"

# Image used by a template (from main.tf)
image t:
    @just _known {{t}}
    @scripts/image-ref.sh {{t}}/main.tf

# True if the image exists in GHCR
image-exists t:
    #!/usr/bin/env bash
    set -euo pipefail
    img="$(just image {{t}})"
    state="$(scripts/image-state.sh "$img")"
    echo "$state: $img"
    [ "$state" = present ]

# Wait (up to 30 min) until CI has pushed the image
wait-image t:
    #!/usr/bin/env bash
    set -euo pipefail
    img="$(just image {{t}})"
    for i in $(seq 1 60); do
      [ "$(scripts/image-state.sh "$img")" = present ] && { echo "present: $img"; exit 0; }
      echo "waiting for $img ($i/60)"; sleep 30
    done
    echo "timeout: $img not in registry" >&2; exit 1

# Publish a template version in Coder (with vars.yaml if it exists)
push t version msg:
    @just _known {{t}}
    coder templates push {{t}} -d {{t}} --name {{version}} --yes --message "{{msg}}" \
      $(test -f vars.yaml && echo --variables-file vars.yaml)

# Image must exist in GHCR; then push template + git tag <template>/<version>
release t version msg:
    @test -z "$(git status --porcelain)" || (echo "Commit your changes first" >&2; exit 1)
    @test "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" || (echo "Push to origin first" >&2; exit 1)
    just image-exists {{t}}
    just push {{t}} {{version}} "{{msg}}"
    git tag -a {{t}}/{{version}} -m "{{msg}}"
    git push origin {{t}}/{{version}}

# Optional: build the image locally (inner Docker) to test a Dockerfile
build-local t:
    @just _known {{t}}
    docker build -t "$(just image {{t}})" {{t}}/build

# Smoke test an image (default: the local build of the main.tf tag)
smoke t image="":
    @just _known {{t}}
    tests/smoke.sh {{t}} "{{ if image == "" { "$(just image " + t + ")" } else { image } }}"

_known t:
    @echo " {{templates}} " | grep -q " {{t}} " || (echo "Unknown template: {{t}}" >&2; exit 1)
