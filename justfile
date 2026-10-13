# Coder templates — build images on x1-hel1 and publish template versions.
#
# The image tag lives in <template>/main.tf (docker_image.workspace.name).
# Patch versions (main.tf only) keep the image tag; minor/major bump it.
#
#   just lint
#   just build node                      # on x1-hel1: builds the tag from main.tf
#   just push node v0.3.1 "message"      # anywhere with `coder login`
#   just release node v0.3.1 "message"   # build (if missing) + push + git tag

templates := "node php-wordpress ops"

default:
    @just --list

# Check formatting, Dockerfiles, JSON and secrets
lint:
    terraform fmt -check -recursive
    hadolint */build/Dockerfile
    for f in */build/*.json; do python3 -m json.tool "$f" >/dev/null || exit 1; done
    gitleaks dir . --no-banner --redact

# Image used by a template (from main.tf)
image t:
    @just _known {{t}}
    @grep -oE 'coder-workspace-[a-z-]+:[^"]+' {{t}}/main.tf

# Build the image named in main.tf (run on x1-hel1)
build t:
    @just _known {{t}}
    docker build -t "$(just image {{t}})" {{t}}/build

# Build only if the image does not exist yet on this host
ensure-image t:
    @just _known {{t}}
    docker image inspect "$(just image {{t}})" >/dev/null 2>&1 || just build {{t}}

# Publish a template version
push t version msg:
    @just _known {{t}}
    coder templates push {{t}} -d {{t}} --name {{version}} --yes --message "{{msg}}"

# ensure-image + push + git tag <template>/<version> (run on x1-hel1)
release t version msg:
    @test -z "$(git status --porcelain)" || (echo "Commit your changes first" >&2; exit 1)
    just ensure-image {{t}}
    just push {{t}} {{version}} "{{msg}}"
    git tag -a {{t}}/{{version}} -m "{{msg}}"
    git push origin {{t}}/{{version}}

_known t:
    @echo " {{templates}} " | grep -q " {{t}} " || (echo "Unknown template: {{t}}" >&2; exit 1)
