#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 h-network
#
# smokeTest — check that the things consumers call still exist and start.
#
# Runs during the build and fails it. The failure mode this exists to catch is
# a silent one: if startAgent is renamed, moved, or stops accepting the
# arguments it used to, the build still succeeds and the image still publishes.
# What a consumer then sees is a terminal that opens, an agent that never
# speaks, and no error anywhere — indistinguishable from an unauthenticated
# CLI, a first-run dialog, or an agent with nothing to say.
#
# Also installed to /usr/local/bin/smokeTest so it can be re-run against a
# container that is already up.
#
# Fast, hermetic, no network. Deliberately proves very little — see the note it
# prints at the end.
set -uo pipefail

fails=0

# check <description> <command...> — runs the command with output suppressed;
# a non-zero exit is a failure, recorded and reported, but does not stop the
# run. Every check reports, so one build shows every problem rather than only
# the first.
check() {
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        printf '  ok      %s\n' "$what"
    else
        printf '  FAILED  %s\n' "$what"
        fails=$((fails + 1))
    fi
}

echo "smokeTest: checking the image's entry points"

# The wrapper every consumer calls. --help is the only subcommand that neither
# launches a CLI nor needs credentials.
check "startAgent --help exits 0" startAgent --help

# On PATH, not merely installed: the CLIs live under $HOME and reach PATH via
# an ENV line in the Dockerfile, which is exactly the kind of thing that breaks
# without any build error.
for cli in claude codex agy; do
    check "$cli is on PATH" command -v "$cli"
done

# Config the CLIs read at startup. Malformed JSON here is not a parse error the
# user sees — the CLI falls back to defaults or stops on the dialog these files
# exist to suppress.
check "~/.claude.json parses as JSON" jq -e . "$HOME/.claude.json"
check "~/.claude/settings.json parses as JSON" jq -e . "$HOME/.claude/settings.json"
check "~/.codex/config.toml parses as TOML" \
    python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$HOME/.codex/config.toml"

echo
if [ "$fails" -ne 0 ]; then
    echo "smokeTest: $fails check(s) FAILED"
    exit 1
fi

# Said out loud on success, because a green build here is easy to read as more
# assurance than it is.
cat <<'EOF'
smokeTest: all checks passed

  This proves only that the entry points exist and start. It does not run a
  model, use credentials, or touch the network, and it says nothing about
  whether any CLI behaves correctly once it is running.
EOF
