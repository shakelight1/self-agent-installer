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

Public one-liner:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/shakelight1/self-agent-installer/v1.0.1/install.sh)"
```

## Windows PowerShell

Public one-liner:

```powershell
irm https://raw.githubusercontent.com/shakelight1/self-agent-installer/v1.0.1/install.ps1 | iex
```

## Public Link

This mode does not require GitHub login or repository access. Anyone who receives the raw URL can run it.

To make the link work, set the GitHub repository visibility to public:

`Settings -> General -> Danger Zone -> Change repository visibility -> Change to public`

Manual public flow:

```bash
git clone --branch v1.0.1 https://github.com/shakelight1/self-agent-installer.git
cd self-agent-installer
bash install.sh
```

Windows:

```powershell
git clone --branch v1.0.1 https://github.com/shakelight1/self-agent-installer.git
cd self-agent-installer
.\install.ps1
```

Use tags such as `v1.0.1` for stable installer behavior. Use `main` only if you want the command to always run the newest script.

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
