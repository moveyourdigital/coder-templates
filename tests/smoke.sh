#!/usr/bin/env bash
# Smoke test for a workspace image: tools work, policy is readable,
# code-server starts. Runs as the image user (coder), without Sysbox.
#
#   tests/smoke.sh <template> <image>
set -euo pipefail

t="${1:?template}"
img="${2:?image}"

# Runs inside the container; expands there, not here.
# shellcheck disable=SC2016
common='
  set -euo pipefail
  test "$(id -un)" = coder
  for c in git curl jq gh docker zsh tmux rg sudo python3; do
    command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }
  done
  git --version; gh --version | sed -n 1p; docker --version
  docker compose version; docker buildx version
  # Claude Code managed policy must be readable by coder (COPY --chmod=0644)
  jq -e . /etc/claude-code/managed-settings.json >/dev/null
  # OneDev CLI and its managed skills (readable by coder)
  tod version
  n=0
  for f in /etc/claude-code/.claude/skills/*/SKILL.md; do test -r "$f" && n=$((n + 1)); done
  test "$n" -ge 8 || { echo "tod skills: $n readable, want 8+" >&2; exit 1; }
  echo "tod skills: $n"
  code-server --version | sed -n 1p
  code-server --auth none --bind-addr 127.0.0.1:13337 >/tmp/cs.log 2>&1 &
  for _ in $(seq 1 30); do
    curl -fs --connect-timeout 2 --max-time 5 -o /dev/null 127.0.0.1:13337/healthz && break
    sleep 1
  done
  curl -fs --connect-timeout 2 --max-time 10 -o /dev/null 127.0.0.1:13337/ || { cat /tmp/cs.log >&2; exit 1; }
  echo "code-server: ok"
'

case "$t" in
  node-js)
    extra='make --version | sed -n 1p; gcc --version | sed -n 1p'
    ;;
  php-wordpress)
    extra='php --version | sed -n 1p; composer --version; wp --version
      php -m | grep -ix mysqli >/dev/null; php -m | grep -ix imagick >/dev/null; mariadb --version'
    ;;
  ops)
    extra='tailscale version | sed -n 1p; ansible --version | sed -n 1p
      borg --version; psql --version; redis-cli --version; pre-commit --version'
    ;;
  *)
    echo "Unknown template: $t" >&2; exit 1
    ;;
esac

docker run --rm --entrypoint bash "$img" -c "$common
$extra
echo 'smoke: ok'"
