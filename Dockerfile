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
        perl \
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

# base installs nothing agent-specific itself. The three agent CLIs
# (claude, codex, agy), their unattended config, and the h-agent launcher +
# profile helpers all come from h-agent's installer, fetched from its repo at
# build time. base's job stops at the environment; here it hands off.
#
# The installer runs as the ubuntu run-user, from /workspace: that is what lets
# it place the CLIs and helper scripts under ~/.local/bin and seed config into
# this user's home — ~/.claude/settings.json, ~/.claude.json (onboarding plus
# trust for /workspace), ~/.codex/config.toml — answering the first-run dialogs
# a headless container cannot. (Claude Code also refuses to run under root, so
# the agent layer belongs to this unprivileged user regardless.)
#
# H_AGENT_VERSION pins the whole agent layer — CLIs, scripts and config — to a
# single h-agent commit for a reproducible image; it tracks main by default.
# h-agent is licensed separately (PolyForm Noncommercial 1.0.0) — see NOTICE.
USER ubuntu
ENV HOME=/home/ubuntu
ENV PATH="/home/ubuntu/.local/bin:${PATH}"
ARG H_AGENT_VERSION=main
RUN cd /workspace \
    && curl -fsSL "https://raw.githubusercontent.com/h-network/h-agent/${H_AGENT_VERSION}/install.sh" \
       | H_AGENT_VERSION="${H_AGENT_VERSION}" PREFIX="$HOME/.local" bash

# base's own files. smokeTest verifies the finished image (build-time QA, so it
# belongs to base, not h-agent) and goes on PATH so it can be re-run in a live
# container. The licence ships beside it per Apache-2.0 section 4(a); NOTICE
# records the third-party software in the image, TRADEMARKS.md the mark policy.
USER root
COPY h-app/smoketest.sh /usr/local/bin/smokeTest
RUN chmod 755 /usr/local/bin/smokeTest

# Login banner (h-app/motd), shown once per interactive terminal via a hook in
# /etc/bash.bashrc. Gated to interactive shells on a TTY and to once per session
# (an exported guard), so it never leaks into an agent's output or a piped
# command. Pure presentation — no network, no side effects.
COPY h-app/motd /usr/local/bin/h-motd
RUN chmod 755 /usr/local/bin/h-motd \
    && printf '%s\n' \
       '' \
       '# h-network/base: show the login banner once, for interactive terminals only' \
       'if [ -z "${H_MOTD_SHOWN:-}" ] && [ -t 1 ]; then' \
       '    case $- in *i*) command -v h-motd >/dev/null 2>&1 && h-motd; export H_MOTD_SHOWN=1 ;; esac' \
       'fi' \
       >> /etc/bash.bashrc

COPY LICENSE NOTICE TRADEMARKS.md /usr/share/doc/h-network-base/

# tmux is environment, not agentic, so its config stays base's. Last, so
# editing it rebuilds only this cheap layer.
USER ubuntu
COPY --chown=ubuntu:ubuntu h-app/tmux.conf /home/ubuntu/.tmux.conf

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
