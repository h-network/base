#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 h-network
#
# startAgent — launch an agent CLI with the container's defaults applied.
#
#   startAgent            # the default CLI ($AGENT_CLI, or claude)
#   startAgent claude
#   startAgent agy
#   startAgent codex
#   startAgent claude --resume     # anything after the CLI name is passed through
#   startAgent --resume            # bare flags go to the default CLI
#
# Each CLI spells "don't stop to ask me" differently — claude
# --dangerously-skip-permissions, agy the same, codex
# --dangerously-bypass-approvals-and-sandbox. Remembering which belongs to
# which is the whole reason this wrapper exists.
#
# Approval prompts are skipped by default: this image is a disposable container
# running as an unprivileged user, which is the environment those flags are
# meant for. Set AGENT_SKIP_PERMISSIONS=0 to keep the prompts — worth doing if
# you bind-mount a host directory you care about, since the container is then
# no longer the only thing at risk.
#
# Only claude can restrict its tool set from the command line; agy and codex
# have no equivalent, so they run with their full set.
set -uo pipefail

usage() {
    cat <<'EOF'
usage: startAgent [claude|agy|codex] [args...]

  claude   --dangerously-skip-permissions, tools limited to
           Bash/Read/Write/Edit/Glob/Grep
  agy      --dangerously-skip-permissions
  codex    --dangerously-bypass-approvals-and-sandbox

With no CLI named, starts $AGENT_CLI (default: claude).
Any further arguments are passed straight to the chosen CLI.

Environment:
  AGENT_CLI               default CLI when none is named (default: claude)
  AGENT_SKIP_PERMISSIONS  1 (default) skips approval prompts; 0 keeps them
  AGENT_CLAUDE_TOOLS      claude's tool list (default:
                          "Bash Read Write Edit Glob Grep"; empty = unrestricted)

Local inference endpoint (claude only — codex and agy refuse):
  AGENT_PROVIDER_URL          endpoint base, e.g. http://10.0.0.5:8000
                              a trailing /v1 is stripped here
  AGENT_PROVIDER_MODEL        model id, exactly as the endpoint serves it
  AGENT_PROVIDER_SMALL_MODEL  optional, defaults to AGENT_PROVIDER_MODEL
  AGENT_PROVIDER_TOKEN        optional, a placeholder is sent if unset

  Use probeProvider <url> to list what an endpoint serves and check that
  claude can talk to it.
EOF
}

cli="${AGENT_CLI:-claude}"
case "${1:-}" in
    claude|agy|codex)   cli="$1"; shift ;;
    -h|--help|help)     usage; exit 0 ;;
    "")                 ;;   # no args — default CLI
    -*)                 ;;   # bare flags belong to the default CLI
    *)
        echo "error: unknown agent CLI '$1' (expected claude, agy or codex)" >&2
        echo "       run 'startAgent --help' for usage" >&2
        exit 2
        ;;
esac

if ! command -v "$cli" >/dev/null 2>&1; then
    echo "error: '$cli' is not installed in this image" >&2
    exit 127
fi

# --- local inference endpoint ---------------------------------------------
#
# Setting AGENT_PROVIDER_URL states an intent: talk to this endpoint, not to the
# vendor. Only claude can be pointed at one cleanly, so the others refuse.
#
# Refusing matters more than supporting. A CLI that ignored these variables
# would start, work, and quietly bill the vendor — the operator would be wrong
# about both cost and where their code went, with nothing anywhere saying so.
# An error the caller has to deal with is the safe failure.
if [ -n "${AGENT_PROVIDER_URL:-}" ]; then
    case "$cli" in
        codex|agy)
            echo "error: $cli cannot use a local inference endpoint" >&2
            echo "       AGENT_PROVIDER_URL is set to '$AGENT_PROVIDER_URL', but only claude" >&2
            echo "       supports one. Refusing rather than starting against the vendor." >&2
            echo "       Use 'startAgent claude', or unset AGENT_PROVIDER_URL to run $cli normally." >&2
            exit 3
            ;;
        claude)
            if [ -z "${AGENT_PROVIDER_MODEL:-}" ]; then
                echo "error: AGENT_PROVIDER_URL is set but AGENT_PROVIDER_MODEL is not" >&2
                echo "       claude would fall back to vendor model names the endpoint does not" >&2
                echo "       serve, and report that as a model error. Set the id the endpoint" >&2
                echo "       actually serves — 'probeProvider $AGENT_PROVIDER_URL' lists them." >&2
                exit 3
            fi

            # A leftover key or base URL from a previous subscription silently
            # outranks what is set below, and the symptom is "it works, but the
            # bill is wrong". Clear the lot before setting our own.
            unset ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL \
                  ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN

            # claude appends /v1/messages itself, so a URL that already carries
            # /v1 becomes /v1/v1/messages — a 404 that surfaces as empty output
            # rather than as an error. Strip it, and accept either form.
            url="${AGENT_PROVIDER_URL%/}"
            url="${url%/v1}"
            url="${url%/}"
            export ANTHROPIC_BASE_URL="$url"

            # claude will not start without a token even when the endpoint
            # ignores it entirely.
            export ANTHROPIC_AUTH_TOKEN="${AGENT_PROVIDER_TOKEN:-local-endpoint-no-token}"

            # All three tiers, because claude picks one internally: set only
            # some and the rest fall back to vendor model names the endpoint
            # does not serve.
            export ANTHROPIC_DEFAULT_OPUS_MODEL="$AGENT_PROVIDER_MODEL"
            export ANTHROPIC_DEFAULT_SONNET_MODEL="$AGENT_PROVIDER_MODEL"
            export ANTHROPIC_DEFAULT_HAIKU_MODEL="${AGENT_PROVIDER_SMALL_MODEL:-$AGENT_PROVIDER_MODEL}"

            echo "startAgent: claude → $ANTHROPIC_BASE_URL (model: $AGENT_PROVIDER_MODEL)" >&2
            ;;
    esac
fi

skip="${AGENT_SKIP_PERMISSIONS:-1}"
tools="${AGENT_CLAUDE_TOOLS-Bash Read Write Edit Glob Grep}"

flags=()
case "$cli" in
    claude)
        [ "$skip" = "1" ] && flags+=(--dangerously-skip-permissions)
        # Unquoted on purpose: the tool list is several arguments, not one.
        [ -n "$tools" ] && flags+=(--tools $tools)
        ;;
    agy)
        [ "$skip" = "1" ] && flags+=(--dangerously-skip-permissions)
        ;;
    codex)
        # codex's own help for this flag: "Intended solely for running in
        # environments that are externally sandboxed" — i.e. this container.
        [ "$skip" = "1" ] && flags+=(--dangerously-bypass-approvals-and-sandbox)
        ;;
esac

exec "$cli" "${flags[@]}" "$@"
