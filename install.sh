#!/usr/bin/env bash
set -euo pipefail

NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PYPI_TRUSTED_HOST="${PYPI_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
NODE_MIRROR="${NODE_MIRROR:-https://npmmirror.com/mirrors/node}"
NODE_CHANNEL="${NODE_CHANNEL:-latest-v22.x}"
INSTALL_HOME="${AGENT_INSTALLER_HOME:-$HOME/.agent-installer}"
NODE_HOME="$INSTALL_HOME/node"
NPM_PREFIX="$INSTALL_HOME/npm-global"
HERMES_VENV="$INSTALL_HOME/hermes-venv"
HERMES_BIN="$HERMES_VENV/bin"

log() {
  printf '\033[1;34m[agent-installer]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[agent-installer]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[agent-installer]\033[0m %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_platform() {
  local kernel arch
  kernel="$(uname -s)"
  arch="$(uname -m)"

  case "$kernel" in
    Darwin) NODE_OS="darwin" ;;
    Linux) NODE_OS="linux" ;;
    *) die "Unsupported system: $kernel. Use install.ps1 on Windows." ;;
  esac

  case "$arch" in
    arm64|aarch64) NODE_ARCH="arm64" ;;
    x86_64|amd64) NODE_ARCH="x64" ;;
    *) die "Unsupported CPU architecture: $arch" ;;
  esac
}

profile_file() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    printf '%s/.zshrc' "$HOME"
  elif [ -n "${BASH_VERSION:-}" ]; then
    printf '%s/.bashrc' "$HOME"
  else
    printf '%s/.profile' "$HOME"
  fi
}

ensure_profile_path() {
  local profile marker line
  profile="$(profile_file)"
  marker="# agent-installer PATH"
  line="export PATH=\"$NODE_HOME/bin:$NPM_PREFIX/bin:$HERMES_BIN:\$PATH\""
  mkdir -p "$(dirname "$profile")"
  touch "$profile"
  if ! grep -Fq "$marker" "$profile"; then
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' "$line"
    } >> "$profile"
    log "Added PATH to $profile"
  fi
  export PATH="$NODE_HOME/bin:$NPM_PREFIX/bin:$HERMES_BIN:$PATH"
}

download_node() {
  local sums filename url tmp
  sums="$(mktemp)"
  tmp="$(mktemp -d)"
  trap 'rm -f "$sums"; rm -rf "$tmp"' RETURN

  log "Downloading Node.js from $NODE_MIRROR/$NODE_CHANNEL"
  curl -fsSL "$NODE_MIRROR/$NODE_CHANNEL/SHASUMS256.txt" -o "$sums"
  filename="$(
    grep "node-v.*-$NODE_OS-$NODE_ARCH.tar.gz$" "$sums" \
      | awk '{print $2}' \
      | head -n 1 \
      || true
  )"
  [ -n "$filename" ] || die "Cannot find Node.js package for $NODE_OS-$NODE_ARCH from mirror."

  url="$NODE_MIRROR/$NODE_CHANNEL/$filename"
  curl -fL "$url" -o "$tmp/$filename"
  rm -rf "$NODE_HOME"
  mkdir -p "$NODE_HOME"
  tar -xzf "$tmp/$filename" -C "$NODE_HOME" --strip-components=1
}

ensure_node() {
  mkdir -p "$INSTALL_HOME" "$NPM_PREFIX"
  export PATH="$NODE_HOME/bin:$NPM_PREFIX/bin:$HERMES_BIN:$PATH"

  if command_exists node && command_exists npm; then
    log "Using existing Node.js: $(node -v)"
  else
    download_node
    log "Installed Node.js: $("$NODE_HOME/bin/node" -v)"
  fi

  npm config set registry "$NPM_REGISTRY" >/dev/null
  npm config set prefix "$NPM_PREFIX" >/dev/null
  ensure_profile_path
}

python_cmd() {
  if command_exists python3; then
    printf 'python3'
  elif command_exists python; then
    printf 'python'
  else
    return 1
  fi
}

ensure_python_and_pip() {
  local py
  py="$(python_cmd)" || die "Python is required for hermes-agent. Install Python 3 first, then rerun this script."
  log "Using Python: $($py --version 2>&1)"
  if [ ! -x "$HERMES_VENV/bin/python" ]; then
    "$py" -m venv "$HERMES_VENV" || die "Python venv is required for hermes-agent. Install Python with venv support, then rerun this script."
  fi
  PYTHON_BIN="$HERMES_VENV/bin/python"
  "$PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1 || true
  "$PYTHON_BIN" -m pip --version >/dev/null 2>&1 || die "pip is required for hermes-agent. Install pip, then rerun this script."
  "$PYTHON_BIN" -m pip config set global.index-url "$PYPI_INDEX_URL" >/dev/null || true
  "$PYTHON_BIN" -m pip config set global.trusted-host "$PYPI_TRUSTED_HOST" >/dev/null || true
}

install_npm_agents() {
  log "Installing OpenClaw, Codex, and Claude Code from $NPM_REGISTRY"
  npm install -g \
    openclaw@latest \
    @openai/codex@latest \
    @anthropic-ai/claude-code@latest \
    --registry="$NPM_REGISTRY"
}

install_hermes() {
  log "Installing Hermes Agent from $PYPI_INDEX_URL"
  "$PYTHON_BIN" -m pip install -U hermes-agent \
    -i "$PYPI_INDEX_URL" \
    --trusted-host "$PYPI_TRUSTED_HOST"
}

print_versions() {
  log "Installed command versions:"
  command_exists openclaw && openclaw --version || warn "openclaw command is not available in current PATH."
  command_exists codex && codex --version || warn "codex command is not available in current PATH."
  command_exists claude && claude --version || warn "claude command is not available in current PATH."
  "$PYTHON_BIN" -m pip show hermes-agent | sed -n 's/^\(Name\|Version\|Home-page\): /hermes-agent \1: /p' || true
}

main() {
  detect_platform
  ensure_node
  ensure_python_and_pip
  install_npm_agents
  install_hermes
  print_versions
  log "Done. Open a new terminal if commands are not found immediately."
}

main "$@"
