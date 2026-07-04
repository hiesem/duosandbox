# Minimal, language-agnostic sandbox for Claude Code and other LLM coding CLIs.
# Drop the .devcontainer/ folder into any project and "Reopen in Container".
ARG NODE_VERSION=20
FROM node:${NODE_VERSION}-slim

# Only what the firewall + agents actually need. --no-install-recommends keeps it lean.
#   iptables/ipset/iproute2 -> egress firewall     dnsutils -> dig (resolve allowlist)
#   jq/aggregate            -> GitHub IP ranges     git/curl/ca-certificates -> agents
#   gawk                    -> firewall parsing      sudo -> run firewall as root at start
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git gawk \
        iptables ipset iproute2 dnsutils jq aggregate \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# --- LLM CLIs --------------------------------------------------------------
# Claude Code is always installed. Toggle others on via build args in devcontainer.json.
# (Package names are examples — adjust INSTALL_* lines to the CLIs you actually want.)
ARG INSTALL_CODEX=false
ARG INSTALL_GEMINI=false
RUN npm install -g @anthropic-ai/claude-code \
    && if [ "$INSTALL_CODEX" = "true" ];  then npm install -g @openai/codex;      fi \
    && if [ "$INSTALL_GEMINI" = "true" ]; then npm install -g @google/gemini-cli; fi \
    && npm cache clean --force

ARG USERNAME=node

# Let the non-root user run ONLY the firewall script as root, without a password.
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh \
    && echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
        > /etc/sudoers.d/${USERNAME}-firewall \
    && chmod 0440 /etc/sudoers.d/${USERNAME}-firewall

# Persisted Claude config dir (mounted as a named volume in devcontainer.json so
# your login survives rebuilds).
ENV CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude
RUN mkdir -p /home/${USERNAME}/.claude \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.claude

USER ${USERNAME}
WORKDIR /workspace
