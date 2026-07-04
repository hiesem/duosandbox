# DuoSandbox: a hardened, network-open, filesystem-isolated dev container.
# The agent can reach the internet freely, but can only see the project mounted
# at /workspace -- the rest of your machine is invisible to it.
#
# No LLM CLI is baked in by default. Add one at build time via the args below,
# or just `npm i -g <cli>` at runtime inside the container.
ARG NODE_VERSION=20
FROM node:${NODE_VERSION}-slim

# Minimal toolchain: git for the agent, curl/ca-certificates for HTTPS.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

# --- Optional LLM CLIs (all OFF by default) --------------------------------
# Flip any to "true" in the devcontainer.json build args. Package names are
# examples -- adjust to whatever you actually use.
ARG INSTALL_CLAUDE=false
ARG INSTALL_CODEX=false
ARG INSTALL_GEMINI=false
RUN if [ "$INSTALL_CLAUDE" = "true" ]; then npm install -g @anthropic-ai/claude-code; fi \
    && if [ "$INSTALL_CODEX" = "true" ];  then npm install -g @openai/codex;          fi \
    && if [ "$INSTALL_GEMINI" = "true" ]; then npm install -g @google/gemini-cli;     fi \
    && npm cache clean --force

# Persist LLM login/config across rebuilds (mounted as a volume in devcontainer.json).
# Harmless if you never install an LLM.
ENV CLAUDE_CONFIG_DIR=/home/node/.claude
RUN mkdir -p /home/node/.claude && chown -R node:node /home/node/.claude

# Non-root. The base image already ships an unprivileged `node` user.
USER node
WORKDIR /workspace
