# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 h-network
#
# setupConfigDir — run a CLI against a separate config dir, seeded from yours.
#
# Auto-loaded in every shell (installed to /etc/profile.d). It is a shell
# *function*, not a standalone script: it has to `export` into your current
# shell, and a subprocess cannot do that.
#
#   setupConfigDir work           # → ~/.claude-work + ~/.codex-work
#   setupConfigDir work --same    # ...and copy the existing logins across
#   setupConfigDir                # show which config dirs this shell uses
#   setupConfigDir default        # back to ~/.claude and ~/.codex
#
# Why a helper instead of just `export CLAUDE_CONFIG_DIR=~/.claude-work`: a bare
# export points the CLI at an EMPTY directory. Nothing carries over, so that
# shell silently runs on the CLI's stock defaults instead of the profile you
# have set up. This copies your profile in first.
#
# "Profile" means the configuration — settings.json, config.toml, and any
# skills/, agents/ or CLAUDE.md you keep alongside them. Not the session state
# (history, projects, sessions), which is what makes the new dir separate, and
# not the credentials unless you ask with --same.
#
# Both CLIs move together, and the names stay under ~/.claude-<name> and
# ~/.codex-<name> — tooling that discovers config dirs generally does so by
# globbing those patterns.

# Bash only — /etc/profile.d is sourced by every POSIX shell, and `local` plus
# the rest below is not portable. Bail out early for non-bash shells.
[ -n "${BASH_VERSION:-}" ] || return 0

setupConfigDir() {
    local name="" same=0 arg

    for arg in "$@"; do
        case "$arg" in
            --same|--same-account) same=1 ;;
            -h|--help|help)
                cat <<'EOF'
usage: setupConfigDir [<name>] [--same]

  <name>     point this shell at its own config dirs:
               ~/.claude-<name>  (CLAUDE_CONFIG_DIR)
               ~/.codex-<name>   (CODEX_HOME)
             Both are seeded with a copy of your current profile — settings,
             skills, agents — but not your session history or logins.

  --same     also copy the existing logins across, so the CLI does not ask you
             to authenticate again.

  default    put this shell back on ~/.claude and ~/.codex.

  (no args)  show which config dirs this shell is currently using.

Applies to THIS shell only. A new shell is back on the default dirs until you
run it again.
EOF
                return 0
                ;;
            -*) echo "error: unknown option '$arg' (try --help)" >&2; return 2 ;;
            *)  [ -z "$name" ] && name="$arg" ;;
        esac
    done

    if [ -z "$name" ]; then
        echo "claude : ${CLAUDE_CONFIG_DIR:-$HOME/.claude (default)}"
        echo "codex  : ${CODEX_HOME:-$HOME/.codex (default)}"
        echo "usage: setupConfigDir <name>   # e.g. 'work' → ~/.claude-work + ~/.codex-work"
        echo "       setupConfigDir --help"
        return 0
    fi

    if [ "$name" = "default" ] || [ "$name" = "shared" ]; then
        unset CLAUDE_CONFIG_DIR CODEX_HOME
        echo "✓ this shell is back on $HOME/.claude and $HOME/.codex."
        return 0
    fi

    # Accept 'work', '.claude-work', or a path ending in one of those. Reject
    # anything with '..' rather than quietly taking its basename — the result
    # would not be what was typed.
    case "$name" in
        *..*)
            echo "error: '..' is not allowed in a config dir name (got '${1}')" >&2
            return 2
            ;;
    esac
    name="${name%/}"
    name="${name##*/}"
    name="${name#.claude-}"
    name="${name#.codex-}"
    case "$name" in
        ""|*[!a-zA-Z0-9._-]*)
            echo "error: config dir name must be alphanumeric, '.', '_' or '-' (got '${1}')" >&2
            return 2
            ;;
    esac

    # _copy_profile <src-dir> <dst-dir> <item...> — an allowlist, not an
    # exclude list: session state and caches are the bulk of a config dir and
    # copying them by accident is worse than missing something.
    _copy_profile() {
        local src="$1" dst="$2" item
        shift 2
        mkdir -p "$dst" || return 1
        [ -d "$src" ] || return 0
        for item in "$@"; do
            [ -e "$src/$item" ] || continue
            [ -e "$dst/$item" ] && continue     # never clobber
            cp -r "$src/$item" "$dst/$item" && echo "  copied $item"
        done
    }

    # _copy_login <src> <dst> — never overwrites a login already there.
    _copy_login() {
        [ -f "$2" ] && return 0
        if [ -f "$1" ]; then
            cp "$1" "$2" && chmod 600 "$2" && echo "  copied login from ${1/#$HOME/\~}"
        else
            echo "warning: --same given but ${1/#$HOME/\~} does not exist" >&2
        fi
    }

    local cdir="$HOME/.claude-$name" xdir="$HOME/.codex-$name"

    echo "claude → ${cdir/#$HOME/\~}"
    _copy_profile "$HOME/.claude" "$cdir" settings.json skills agents CLAUDE.md || return 1

    # Claude Code keeps first-run state in .claude.json *inside* the config dir
    # (at $HOME/.claude.json only for the default dir). Without it a new dir is
    # treated as a first run and you get the theme picker and onboarding before
    # you can do anything.
    #
    # Written minimally rather than copied: the real .claude.json accumulates
    # project history, userID and machineID — session state, which is exactly
    # what a separate config dir is meant not to inherit. Preferences that do
    # matter, theme included, live in settings.json, which is copied above.
    if [ ! -f "$cdir/.claude.json" ]; then
        printf '{\n  "hasCompletedOnboarding": true\n}\n' > "$cdir/.claude.json" \
            && echo "  wrote .claude.json (skips first-run onboarding)"
    fi
    echo "codex  → ${xdir/#$HOME/\~}"
    _copy_profile "$HOME/.codex" "$xdir" config.toml AGENTS.md || return 1

    if [ "$same" -eq 1 ]; then
        _copy_login "$HOME/.claude/.credentials.json" "$cdir/.credentials.json"
        _copy_login "$HOME/.codex/auth.json"          "$xdir/auth.json"
    fi

    unset -f _copy_profile _copy_login

    export CLAUDE_CONFIG_DIR="$cdir"
    export CODEX_HOME="$xdir"

    if [ "$same" -ne 1 ] && [ ! -f "$cdir/.credentials.json" ]; then
        echo "  no login copied — the CLI will ask you to authenticate (--same copies it)"
    fi
}
