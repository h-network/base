#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 h-network
#
# probeProvider — list what a local inference endpoint serves, and check that
# claude can actually talk to it.
#
#   probeProvider http://10.0.0.5:8000
#   probeProvider http://10.0.0.5:8000 some-model-id
#
# Serving models and being usable by claude are different things: claude talks
# to /v1/messages, which plenty of OpenAI-shaped servers do not implement. So
# this lists the ids, then sends a real request to the real route.
#
# The ids are printed rather than described because they must match byte for
# byte. An ollama id carries a tag — `gpt-oss:20b` mistyped as `gpt-oss-20b`
# comes back later as a model error, which reads like the model is broken
# rather than misspelled.
set -uo pipefail

# Long, because a model that has to load answers in tens of seconds cold and
# under a second warm. A short timeout does not measure the endpoint, it
# measures whether the endpoint happened to be warm.
TIMEOUT="${PROBE_TIMEOUT:-90}"
LIST_TIMEOUT=10

usage() {
    cat <<'EOF'
usage: probeProvider <url> [model-id]

  <url>       endpoint base, e.g. http://10.0.0.5:8000
              a trailing /v1 is stripped
  [model-id]  which served id to verify with; defaults to the first one listed

Lists the models an endpoint serves, then verifies claude can use it by
POSTing to <url>/v1/messages.

  PROBE_TIMEOUT   seconds to wait for the verification request (default: 90)

Exit: 0 usable by claude, 1 not usable, 2 bad arguments.
EOF
}

case "${1:-}" in
    -h|--help|help|"") usage; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
esac

# Same stripping as startAgent: claude appends /v1/messages itself, so a base
# URL carrying /v1 would produce /v1/v1/messages.
url="${1%/}"; url="${url%/v1}"; url="${url%/}"
want_model="${2:-}"

echo "probeProvider: $url"
echo

# --- what does it serve? ---------------------------------------------------
#
# OpenAI-compatible first (vLLM and most others), then ollama's own route.
models=""
served_by=""

body="$(curl -fsS -m "$LIST_TIMEOUT" "$url/v1/models" 2>/dev/null)"
if [ -n "$body" ]; then
    models="$(printf '%s' "$body" | jq -r '.data[]?.id // empty' 2>/dev/null)"
    [ -n "$models" ] && served_by="$url/v1/models"
fi

if [ -z "$models" ]; then
    body="$(curl -fsS -m "$LIST_TIMEOUT" "$url/api/tags" 2>/dev/null)"
    if [ -n "$body" ]; then
        models="$(printf '%s' "$body" | jq -r '.models[]?.name // empty' 2>/dev/null)"
        [ -n "$models" ] && served_by="$url/api/tags"
    fi
fi

if [ -z "$models" ]; then
    echo "could not list models"
    echo "  tried $url/v1/models and $url/api/tags"
    echo "  the endpoint is unreachable, or serves neither route"
    exit 1
fi

echo "serves (from $served_by):"
printf '  %s\n' $models
echo

# --- verify claude can use it ----------------------------------------------
#
# With a REAL served id. vLLM answers an unknown model with 404 and a
# NotFoundError body — identical, from out here, to the route not existing at
# all. Probing with a made-up id would therefore condemn a working endpoint.
if [ -n "$want_model" ]; then
    if ! printf '%s\n' $models | grep -qxF "$want_model"; then
        echo "error: '$want_model' is not served by this endpoint" >&2
        echo "       pick one of the ids listed above, exactly as printed" >&2
        exit 1
    fi
    probe_model="$want_model"
else
    probe_model="$(printf '%s\n' $models | head -1)"
fi

echo "verifying /v1/messages with '$probe_model' (up to ${TIMEOUT}s)..."

out="$(curl -sS -m "$TIMEOUT" -o /tmp/probe.$$ -w '%{http_code}' \
    -X POST "$url/v1/messages" \
    -H 'content-type: application/json' \
    -H 'anthropic-version: 2023-06-01' \
    -H "x-api-key: ${AGENT_PROVIDER_TOKEN:-local-endpoint-no-token}" \
    -d "$(jq -nc --arg m "$probe_model" \
        '{model:$m, max_tokens:1, messages:[{role:"user", content:"hi"}]}')" \
    2>/dev/null)"
rc=$?
resp="$(cat /tmp/probe.$$ 2>/dev/null)"
rm -f /tmp/probe.$$

# curl 28 is the timeout. Reported separately from every other failure on
# purpose: "did not answer in time" and "will not work" look the same from the
# client and mean opposite things — wait and retry, versus stop and pick
# another endpoint. Saying only "failed" sends someone to debug the wrong one.
if [ "$rc" -eq 28 ]; then
    echo
    echo "NO ANSWER within ${TIMEOUT}s"
    echo "  the endpoint accepted the connection but did not reply in time"
    echo "  a cold model can take this long to load — retry, or raise"
    echo "  PROBE_TIMEOUT, before concluding the endpoint is unusable"
    exit 1
fi

if [ "$rc" -ne 0 ]; then
    echo
    echo "NOT USABLE — could not complete the request (curl exit $rc)"
    exit 1
fi

if printf '%s' "$resp" | jq -e '.type == "message"' >/dev/null 2>&1; then
    echo
    echo "USABLE by claude"
    echo
    echo "  AGENT_PROVIDER_URL=$url"
    echo "  AGENT_PROVIDER_MODEL=$probe_model"
    echo "  startAgent claude"
    exit 0
fi

# A served id that still 404s means the route is missing, not the model.
if [ "$out" = "404" ]; then
    echo
    echo "NOT USABLE — /v1/messages returned 404 for a model this endpoint serves"
    echo "  the model is fine; the endpoint does not implement the Anthropic"
    echo "  messages route, so claude cannot talk to it"
    exit 1
fi

echo
echo "NOT USABLE — HTTP $out, and the reply was not an Anthropic message"
printf '%s\n' "$resp" | head -20 | sed 's/^/  /'
exit 1
