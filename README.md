# DuoSandbox (drop-in dev container)

A minimal, language-agnostic VS Code dev container that runs **Claude Code** (and,
optionally, other LLM coding CLIs) inside a **default-deny network sandbox**. Drop it
into any project and "Reopen in Container" — nothing else in the repo is assumed.

## What's in the box

| File | Role |
|------|------|
| `.devcontainer/Dockerfile` | `node:20-slim` + only the firewall toolchain + the LLM CLIs |
| `.devcontainer/devcontainer.json` | caps, workspace mount, config volume, runs the firewall on start |
| `.devcontainer/init-firewall.sh` | iptables + ipset egress allowlist (default-deny) |

The network sandbox is the whole point: outbound traffic is **dropped by default**,
and only an allowlist can get out — Anthropic's API + login (the `160.79.104.0/23`
range that covers `api.anthropic.com`, `claude.ai`, and `platform.claude.com`), npm,
GitHub, plus anything you add.

## Use it

1. Copy the `.devcontainer/` folder into the root of any project.
2. In VS Code: **Command Palette → Dev Containers: Reopen in Container**.
3. On first start the firewall configures itself, then you `claude` in the terminal.
   (Auth persists across rebuilds via a shared named volume.)

## Customize

- **Allow more domains** (private registry, another provider, an API your code calls):
  set `EXTRA_ALLOWED_DOMAINS` in `devcontainer.json`, e.g.
  `"EXTRA_ALLOWED_DOMAINS": "api.openai.com,generativelanguage.googleapis.com"`,
  or drop a `.devcontainer/allowed-domains.txt` (one host per line) into the project.
  Entries may be hostnames **or raw IPs/CIDRs** (e.g. `10.0.0.0/8`). No need to edit
  the firewall script.
- **Add other LLM CLIs**: flip `INSTALL_CODEX` / `INSTALL_GEMINI` to `"true"` in the
  build args (adjust the package names in the Dockerfile to the CLIs you want), and
  add their API domains to the allowlist as above.
- **Skip GitHub ranges**: set `ALLOW_GITHUB` to `"false"` for a smaller, faster start.
- **Per-project auth** instead of shared: append `-${devcontainerId}` to the volume
  `source` name in `devcontainer.json`.

## Security caveat

Container-level isolation shares the host kernel, and with
`--dangerously-skip-permissions` a malicious repo can still exfiltrate anything the
container can reach — including the mounted `~/.claude` credentials. Keep the
allowlist narrow, don't mount SSH/cloud creds, and prefer trusted repos + scoped
tokens. For a harder boundary, run under a microVM (Docker Sandboxes) or add gVisor
(`--runtime=runsc`).

## License

[MIT](LICENSE). Derived from Anthropic's MIT-licensed
[Claude Code reference dev container](https://github.com/anthropics/claude-code/tree/main/.devcontainer).
