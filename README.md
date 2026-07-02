# Agent Installer

Installs the latest mirrored versions of:

- OpenClaw: `openclaw`
- Hermes Agent: `hermes-agent`
- Codex: `@openai/codex`
- Claude Code: `@anthropic-ai/claude-code`

The scripts use China-friendly mirrors by default:

- npm: `https://registry.npmmirror.com`
- PyPI: `https://pypi.tuna.tsinghua.edu.cn/simple`
- Node.js: `https://npmmirror.com/mirrors/node`

## macOS / Linux

```bash
/bin/bash -c "$(curl -fsSL https://gitee.com/YOUR_ORG/agent-installer/raw/main/install.sh)"
```

## Windows PowerShell

```powershell
irm https://gitee.com/YOUR_ORG/agent-installer/raw/main/install.ps1 | iex
```

## Access Control Without A Server

There is no real access control for a public raw URL. Anyone who receives it can run it.

Use one of these lightweight options instead:

1. Put this repository in a private GitHub/Gitee repository and add approved users as collaborators.
2. Ask users to authenticate with Git first, then run the installer from a local clone.
3. Use a fixed tag such as `v1.0.0` for stable installer behavior.

Example private-repo flow:

```bash
git clone git@gitee.com:YOUR_ORG/agent-installer.git
cd agent-installer
bash install.sh
```

Windows:

```powershell
git clone git@gitee.com:YOUR_ORG/agent-installer.git
cd agent-installer
.\install.ps1
```

If you need a one-line command and access control at the same time, use a private repository plus a short-lived personal access token. Do not embed long-lived tokens in shared links.

## Configuration

These environment variables can override mirrors:

- `NPM_REGISTRY`
- `PYPI_INDEX_URL`
- `PYPI_TRUSTED_HOST`
- `NODE_MIRROR`
- `NODE_CHANNEL`
- `AGENT_INSTALLER_HOME`

The default install location is:

- macOS/Linux: `~/.agent-installer`
- Windows: `%USERPROFILE%\.agent-installer`

Hermes Agent is installed into a dedicated Python virtual environment under the install location. The installer writes user-level PATH entries only. It does not require `sudo` or Administrator by default.
