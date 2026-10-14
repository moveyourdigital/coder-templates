#!/bin/sh
# tod wrapper for Coder workspaces. Starts the real binary with:
#
#   token:      ONEDEV_ACCESS_TOKEN, else the Coder user secret ONEDEV_TOKEN,
#               else the tod config file (tod config set)
#   server URL: ONEDEV_SERVER_URL (user secret), else the tod config file,
#               else the template default ONEDEV_DEFAULT_SERVER_URL
#               (template variable onedev_url)
tod=/usr/local/lib/tod/tod

if [ -z "${ONEDEV_ACCESS_TOKEN+set}" ] && [ -n "${ONEDEV_TOKEN:-}" ]; then
  ONEDEV_ACCESS_TOKEN="$ONEDEV_TOKEN"
  export ONEDEV_ACCESS_TOKEN
fi

if [ -z "${ONEDEV_SERVER_URL+set}" ] && [ -n "${ONEDEV_DEFAULT_SERVER_URL:-}" ] \
  && [ -z "$("$tod" config get server-url 2>/dev/null)" ]; then
  ONEDEV_SERVER_URL="$ONEDEV_DEFAULT_SERVER_URL"
  export ONEDEV_SERVER_URL
fi

exec "$tod" "$@"
