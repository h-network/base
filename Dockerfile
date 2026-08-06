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

# Agent CLIs, via their curl installers, as the run user.
# These always fetch the latest release, so a rebuild refreshes them.
USER ubuntu
ENV HOME=/home/ubuntu
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh \
    && curl -fsSL https://antigravity.google/cli/install.sh | bash

ENV PATH="/home/ubuntu/.local/bin:/home/ubuntu/.codex/bin:${PATH}"

# Helpers. startAgent goes on PATH; setupConfigDir has to be a shell function
# (it exports into the calling shell), so it is installed to /etc/profile.d and
# picked up by any login shell.
USER root
COPY startAgent.sh /usr/local/bin/startAgent
COPY setupconfigdir.sh /etc/profile.d/setupconfigdir.sh
RUN chmod 755 /usr/local/bin/startAgent && chmod 644 /etc/profile.d/setupconfigdir.sh

# Apache-2.0 section 4(a) asks that recipients of the work get a copy of the
# licence. The scripts above are the work, so the licence ships beside them.
# NOTICE records that the rest of the image is third-party software under its
# own terms.
COPY LICENSE NOTICE /usr/share/doc/h-network-base/
USER ubuntu

# tmux config — last, so editing it rebuilds only this cheap layer
COPY --chown=ubuntu:ubuntu tmux.conf /home/ubuntu/.tmux.conf

# The CI build gets these from docker/metadata-action; declaring them here means
# a local `docker compose build` produces the same metadata.
LABEL org.opencontainers.image.title="h-network/base" \
      org.opencontainers.image.description="A general-purpose development container: the Claude, Codex and Antigravity CLIs plus everyday dev tooling, on Ubuntu 24.04." \
      org.opencontainers.image.source="https://github.com/h-network/base" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /workspace
CMD ["/bin/bash"]
