# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 h-network
#
# A general-purpose dev container: the three agent CLIs plus everyday tooling.
#
#   docker compose build
#   docker compose run --rm dev
#
# Runs as the `ubuntu` user (uid 1000) that the base image already ships — not
# root, because the agent CLIs misbehave there (Claude Code refuses
# --dangerously-skip-permissions under root). No entrypoint, no uid juggling:
# uid 1000 is the first user on a stock Ubuntu host, so bind mounts line up.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=Europe/Amsterdam

# ca-certificates, curl, sudo and locales aren't on the list below but are
# needed to make it work: TLS, the agent-CLI installers, scripts that shell out
# to sudo, and UTF-8 output.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        sudo \
        locales \
        git \
        jq \
        openssh-client \
        tmux \
        vim-tiny \
        python3 \
        python3-venv \
        python3-pip \
        build-essential \
    && locale-gen en_US.UTF-8 \
    # vim-tiny installs as /usr/bin/vim.tiny and only registers `vi`
    && update-alternatives --install /usr/bin/vim vim /usr/bin/vim.tiny 10 \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI — no curl one-liner exists, so this uses GitHub's apt repo.
RUN install -d -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
         -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# The `ubuntu` user already exists at uid 1000 and is in the sudo group; it just
# needs a NOPASSWD rule (sudo isn't in the base image) and a workspace.
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu \
    && mkdir -p /workspace && chown ubuntu:ubuntu /workspace

# h-agent and pinned agent CLIs (claude, codex, agy), via h-agent's installer, as the run user.
# CLI versions are pinned by h-agent's installer rather than fetched unpinned on rebuild.
USER ubuntu
ENV HOME=/home/ubuntu
RUN curl -fsSL https://raw.githubusercontent.com/h-network/h-agent/main/install.sh | bash

ENV PATH="/home/ubuntu/.local/bin:/home/ubuntu/.codex/bin:${PATH}"

# Claude Code keeps first-run state in ~/.claude.json and treats a missing file
# as a first run: the theme picker comes up before the CLI is usable, which a
# non-interactive container cannot answer.
#
# The "Do you trust this folder?" prompt is keyed by absolute path, so it cannot
# be answered for directories that do not exist yet — but WORKDIR below is
# /workspace, which is where an agent starts unless told otherwise, and that one
# is known now. Anywhere else still prompts on first use.
#
# Merged rather than written flat, because this file is also where the CLI
# later keeps machineID, the logged-in account and per-project history —
# overwriting it wholesale is only safe while it is still empty.
RUN tmp="$(mktemp)" \
    && { [ -s "$HOME/.claude.json" ] && cat "$HOME/.claude.json" || echo '{}'; } \
       | jq '.hasCompletedOnboarding = true \
             | .projects["/workspace"].hasTrustDialogAccepted = true \
             | .projects["/workspace"].hasCompletedProjectOnboarding = true' > "$tmp" \
    && mv "$tmp" "$HOME/.claude.json"

# Helpers. setupConfigDir has to be a shell function (it exports into the
# calling shell), so it is installed to /etc/profile.d and picked up by any
# login shell.
USER root
COPY setupconfigdir.sh /etc/profile.d/setupconfigdir.sh
COPY smoketest.sh /usr/local/bin/smokeTest
COPY probeprovider.sh /usr/local/bin/probeProvider
COPY seedprofile.sh /usr/local/bin/seedProfile
RUN chmod 755 /usr/local/bin/smokeTest \
                /usr/local/bin/probeProvider /usr/local/bin/seedProfile \
    && chmod 644 /etc/profile.d/setupconfigdir.sh

# Apache-2.0 section 4(a) asks that recipients of the work get a copy of the
# licence. The scripts above are the work, so the licence ships beside them.
# NOTICE records that the rest of the image is third-party software under its
# own terms. TRADEMARKS.md defines the project's trademark policy.
COPY LICENSE NOTICE TRADEMARKS.md /usr/share/doc/h-network-base/
USER ubuntu

# CLI defaults for unattended use. Both CLIs stop on a first-run dialog that a
# headless container cannot answer — the theme picker and the bypass-permissions
# acceptance for claude, the update prompt for codex — and a stopped agent looks
# identical to an idle one: no error, no exit code, no log line.
#
# These are defaults, not policy: a consumer that ships its own settings.json
# replaces this file wholesale.
COPY --chown=ubuntu:ubuntu claude-settings.json /home/ubuntu/.claude/settings.json
COPY --chown=ubuntu:ubuntu codex-config.toml /home/ubuntu/.codex/config.toml

# tmux config — last, so editing it rebuilds only this cheap layer
COPY --chown=ubuntu:ubuntu tmux.conf /home/ubuntu/.tmux.conf

# Fail the build if the entry points a consumer calls are missing or broken.
# Runs as ubuntu, after everything is in place, so it checks the image as it
# will actually be used — $HOME and PATH included.
RUN smokeTest

# The CI build gets these from docker/metadata-action; declaring them here means
# a local `docker compose build` produces the same metadata.
LABEL org.opencontainers.image.title="h-network/base" \
      org.opencontainers.image.description="A general-purpose development container: the Claude, Codex and Antigravity CLIs plus everyday dev tooling, on Ubuntu 24.04." \
      org.opencontainers.image.source="https://github.com/h-network/base" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /workspace
CMD ["/bin/bash"]
