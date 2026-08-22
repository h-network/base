#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 h-network
#
# seedProfile — create a config dir for one CLI, carrying the image's defaults.
#
#   seedProfile claude work        # → ~/.claude-work, prints CLAUDE_CONFIG_DIR=...
#   seedProfile codex work         # → ~/.codex-work,  prints CODEX_HOME=...
#   eval "$(seedProfile --export claude work)"
#
# Pointing a CLI at a fresh directory does NOT fall back to the defaults in
# ~/.claude — measured, not assumed: `CLAUDE_CONFIG_DIR=~/.claude-test claude`
# stops on the theme picker. So an automated caller that creates a profile dir
# and starts an agent against it gets a process that opens, waits for a keypress
# nobody will press, and looks exactly like an idle agent.
#
# This is the non-interactive counterpart to setupConfigDir: that one is a shell
# function for a person, exports into their shell, and does both CLIs at once.
# This takes one CLI, touches no environment, and prints what to set — which is
# what a caller that is not a shell needs.
#
# Everything is copied from the live default dir at runtime, never from a file
# committed alongside this script. Two copies of the same defaults would drift,
# and the one in the image is the one that is true.
set -uo pipefail

usage() {
    cat <<'EOF'
usage: seedProfile [--export] <claude|codex> <name>

  Creates the profile dir for one CLI and seeds it with the defaults from the
  image's own config dir — settings, and the answers to the first-run dialogs.

  claude <name>   → ~/.claude-<name>   prints CLAUDE_CONFIG_DIR=<dir>
  codex  <name>   → ~/.codex-<name>    prints CODEX_HOME=<dir>

  --export        print as `export VAR=dir`, for eval

Existing files are never overwritten, so re-running is safe. Credentials are
not copied: a seeded profile is unauthenticated by design.

agy is not supported — it has no config-dir override; see the error it prints.

Exit: 0 seeded, 2 bad arguments, 3 unsupported CLI.
EOF
}

export_form=0
if [ "${1:-}" = "--export" ]; then export_form=1; shift; fi

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
esac

cli="${1:-}"
name="${2:-}"

if [ -z "$cli" ] || [ -z "$name" ]; then
    usage >&2
    exit 2
fi

# Same rule as setupConfigDir: reject '..' rather than quietly taking the
# basename, which would silently seed a directory nobody asked for.
case "$name" in
    *..*) echo "error: '..' is not allowed in a profile name (got '$name')" >&2; exit 2 ;;
esac
name="${name%/}"; name="${name##*/}"
name="${name#.claude-}"; name="${name#.codex-}"
case "$name" in
    ""|*[!a-zA-Z0-9._-]*)
        echo "error: profile name must be alphanumeric, '.', '_' or '-' (got '$name')" >&2
        exit 2
        ;;
esac

# copy_if_absent <src> <dst> — never clobbers. Re-running must not undo
# whatever the CLI has since written into the profile.
copy_if_absent() {
    [ -e "$2" ] && return 0
    [ -e "$1" ] || return 0
    cp -r "$1" "$2"
}

case "$cli" in
    claude)
        dir="$HOME/.claude-$name"
        mkdir -p "$dir" || exit 1
        copy_if_absent "$HOME/.claude/settings.json" "$dir/settings.json"
        for item in skills agents CLAUDE.md; do
            copy_if_absent "$HOME/.claude/$item" "$dir/$item"
        done

        # With CLAUDE_CONFIG_DIR set, claude keeps first-run state in
        # .claude.json *inside* that dir rather than at $HOME/.claude.json.
        # Written from the default file rather than copied wholesale: the real
        # one accumulates machineID, the account and project history, which is
        # session state a separate profile exists not to inherit.
        if [ ! -f "$dir/.claude.json" ]; then
            { [ -s "$HOME/.claude.json" ] && cat "$HOME/.claude.json" || echo '{}'; } \
                | jq '{hasCompletedOnboarding: true,
                       projects: (.projects // {} | with_entries(
                           select(.key == "/workspace")
                           | .value |= {hasTrustDialogAccepted: (.hasTrustDialogAccepted // true),
                                        hasCompletedProjectOnboarding: (.hasCompletedProjectOnboarding // true)}))}' \
                > "$dir/.claude.json" || exit 1
        fi

        var=CLAUDE_CONFIG_DIR
        ;;
    codex)
        dir="$HOME/.codex-$name"
        mkdir -p "$dir" || exit 1
        copy_if_absent "$HOME/.codex/config.toml" "$dir/config.toml"
        copy_if_absent "$HOME/.codex/AGENTS.md" "$dir/AGENTS.md"
        var=CODEX_HOME
        ;;
    agy)
        # Refusing rather than creating a directory that does nothing. agy
        # resolves its state relative to HOME, under ~/.gemini/antigravity-cli/,
        # with no environment variable to point it elsewhere — so a per-profile
        # dir cannot be handed to it the way the other two accept one.
        echo "error: agy has no config-dir override" >&2
        echo "       it reads ~/.gemini/antigravity-cli/ relative to HOME, and its" >&2
        echo "       credential lives at ~/.gemini/antigravity-cli/antigravity-oauth-token," >&2
        echo "       separate from claude's and codex's rather than shared with them." >&2
        echo "       Separating agy profiles means separating HOME, which is a bigger" >&2
        echo "       change than this command should make silently." >&2
        exit 3
        ;;
    *)
        echo "error: unknown CLI '$cli' (expected claude or codex)" >&2
        exit 2
        ;;
esac

if [ "$export_form" -eq 1 ]; then
    echo "export $var=$dir"
else
    echo "$var=$dir"
fi
