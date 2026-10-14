#!/bin/sh
# tod wrapper: tod reads ONEDEV_ACCESS_TOKEN. Coder user secrets may provide
# the token as ONEDEV_TOKEN instead; use it when ONEDEV_ACCESS_TOKEN is unset.
# ONEDEV_SERVER_URL is read by tod directly. Without both, tod uses its config
# file (tod config set).
if [ -z "${ONEDEV_ACCESS_TOKEN+set}" ] && [ -n "${ONEDEV_TOKEN:-}" ]; then
  ONEDEV_ACCESS_TOKEN="$ONEDEV_TOKEN"
  export ONEDEV_ACCESS_TOKEN
fi
exec /usr/local/lib/tod/tod "$@"
