FROM node:20

# Create a non-root user to run Claude Code
RUN useradd -m -s /bin/bash claude

# Switch to non-root user
USER claude

WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash

# Set PATH to include Claude Code installation
ENV PATH="/home/claude/.local/bin:${PATH}"

# Read API key from build argument or runtime environment
ENV ANTHROPIC_API_KEY=""
ENV CLAUDE_CODE_OAUTH_TOKEN=""

WORKDIR /app

# Default command: launch Claude in interactive mode
ENTRYPOINT ["claude"]

# Default prompt (can be overridden when running the container)
CMD []