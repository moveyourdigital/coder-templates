# Coder templates — images are built by GitHub Actions and pushed to GHCR.
#
# The image reference is in <template>/main.tf (docker_image.workspace.name).
# Patch versions (main.tf only) keep the image tag; minor/major bump it.
#
#   just lint
#   just image node-js                     # image used by the template
#   just wait-image node-js                # wait until CI has pushed it
#   just release node-js v0.4.1 "message"  # check image, push template, git tag
#   just build-local node-js               # optional local test build

templates := "node-js php-wordpress ops"

default:
    @just --list

# Check formatting, Dockerfiles, JSON and secrets
lint:
    terraform fmt -check -recursive
    hadolint --config .hadolint.yaml */build/Dockerfile
    for f in */build/*.json; do python3 -m json.tool "$f" >/dev/null || exit 1; done
    gitleaks dir . --no-banner --redact

# Image used by a template (from main.tf)
image t:
    @just _known {{t}}
    @grep -oE 'ghcr\.io/moveyourdigital/coder-workspace-[a-z-]+:[^"]+' {{t}}/main.tf | head -1

# True if the image exists in GHCR
image-exists t:
    @docker manifest inspect "$(just image {{t}})" >/dev/null 2>&1 \
      && echo "present: $(just image {{t}})" \
      || (echo "missing: $(just image {{t}})" >&2; exit 1)

# Wait (up to 30 min) until CI has pushed the image
wait-image t:
    #!/usr/bin/env bash
    set -euo pipefail
    img="$(just image {{t}})"
    for i in $(seq 1 60); do
      docker manifest inspect "$img" >/dev/null 2>&1 && { echo "present: $img"; exit 0; }
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

_known t:
    @echo " {{templates}} " | grep -q " {{t}} " || (echo "Unknown template: {{t}}" >&2; exit 1)
