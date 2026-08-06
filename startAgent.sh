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
