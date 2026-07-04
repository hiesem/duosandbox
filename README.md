# DuoSandbox (drop-in dev container)

A minimal, hardened VS Code dev container that gives an AI coding agent (or any
tool) **full internet access but no access to your machine**. Drop the
`.devcontainer/` folder into any project and "Reopen in Container": the agent can
freely edit the mounted project and reach any server online, while your home
directory, SSH keys, other repos, and OS files stay invisible to it.

## Threat model

- ✅ **Network: fully open.** The agent can call any API / server on the internet.
  No firewall, no allowlist, no special capabilities.
- ✅ **Filesystem: isolated.** Only the current project is mounted (`/workspace`).
  Nothing else on your machine is visible, so the agent can't read or delete it.
- ✅ **Host: protected against accidents.** Runs as a non-root user with all Linux
  capabilities dropped, `no-new-privileges`, a PID limit (an accidental fork bomb
  can't exhaust the host), and `--init` for clean process reaping.

This defends against **accidents** — a stray `rm -rf`, a runaway script. It is a
shared-kernel container, not a VM, so it is not a hard boundary against
*deliberately* malicious code (see Caveats).

## What's in the box

| File | Role |
|------|------|
| `.devcontainer/Dockerfile` | `node:20-slim` + git. No LLM baked in. |
| `.devcontainer/devcontainer.json` | project-only mount, hardening flags, non-root |

## Use it

1. Copy `.devcontainer/` into the root of any project.
2. VS Code: **Command Palette → Dev Containers: Reopen in Container**.
3. Install/run whatever LLM CLI you want (below), or add a VS Code extension.

## Add an LLM

Nothing ships in the image by default — pick your tool:

- **At runtime** (quickest): in the container terminal,
  `npm i -g @anthropic-ai/claude-code` (or `@openai/codex`, `@google/gemini-cli`),
  then run it. Login/config persists via the `duosandbox-config` volume.
- **At build time**: set `INSTALL_CLAUDE` / `INSTALL_CODEX` / `INSTALL_GEMINI` to
  `"true"` in the `devcontainer.json` build args and rebuild.
- **VS Code extension**: add `"anthropic.claude-code"` to
  `customizations.vscode.extensions`.

Python-based tools (e.g. `aider`) need Python added to the Dockerfile.

## Tuning

- **Resource caps**: uncomment `--memory` / `--cpus` in `runArgs` to bound host
  resource use.
- **If something needs a capability** (rare for a non-root editor), relax
  `--cap-drop=ALL`.

## Caveats

- **Shared kernel**: strong against accidents, not a guarantee against a determined
  exploit. For genuinely untrusted code, use a microVM (e.g. Docker Sandboxes).
- **The workspace is real**: writes to `/workspace` hit your actual project on disk,
  so the agent *can* mangle or fill the repo it's working in — that's by design.
  Use git so you can roll back.
- **Only what you mount is reachable**: don't add extra host mounts or the Docker
  socket unless you intend the agent to reach them.

## License

[MIT](LICENSE). Originally derived from Anthropic's
[Claude Code reference dev container](https://github.com/anthropics/claude-code/tree/main/.devcontainer).
