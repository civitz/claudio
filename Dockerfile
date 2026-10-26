FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run Claude Code
RUN useradd -m -s /bin/bash claude

# Switch to non-root user
USER claude

# Claude Code version to install (stable, latest or x.y.z). claudio.ps1 passes
# the exact version when rebuilding, so only this layer is invalidated.
ARG CLAUDE_CODE_VERSION=latest

WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_VERSION"

# Set PATH to include Claude Code installation
ENV PATH="/home/claude/.local/bin:${PATH}"

ENV LANG=C.UTF-8

# Containers run with --rm, so in-place updates would be lost on exit:
# claudio.ps1 rebuilds the image instead
ENV DISABLE_AUTOUPDATER=1

# Credentials (CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY) are not baked in:
# they come from <home>/.env via --env-file at run time

WORKDIR /app

# Default command: launch Claude in interactive mode
ENTRYPOINT ["claude"]

# Default prompt (can be overridden when running the container)
CMD []
