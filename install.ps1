$ErrorActionPreference = "Stop"

$NpmRegistry = if ($env:NPM_REGISTRY) { $env:NPM_REGISTRY } else { "https://registry.npmmirror.com" }
$PypiIndexUrl = if ($env:PYPI_INDEX_URL) { $env:PYPI_INDEX_URL } else { "https://pypi.tuna.tsinghua.edu.cn/simple" }
$PypiTrustedHost = if ($env:PYPI_TRUSTED_HOST) { $env:PYPI_TRUSTED_HOST } else { "pypi.tuna.tsinghua.edu.cn" }
$NodeMirror = if ($env:NODE_MIRROR) { $env:NODE_MIRROR.TrimEnd("/") } else { "https://npmmirror.com/mirrors/node" }
$NodeChannel = if ($env:NODE_CHANNEL) { $env:NODE_CHANNEL } else { "latest-v22.x" }
$InstallHome = if ($env:AGENT_INSTALLER_HOME) { $env:AGENT_INSTALLER_HOME } else { Join-Path $env:USERPROFILE ".agent-installer" }
$NodeHome = Join-Path $InstallHome "node"
$NpmPrefix = Join-Path $InstallHome "npm-global"
$HermesVenv = Join-Path $InstallHome "hermes-venv"
$HermesScripts = Join-Path $HermesVenv "Scripts"
$HermesPython = Join-Path $HermesScripts "python.exe"

function Write-Step($Message) {
  Write-Host "[agent-installer] $Message" -ForegroundColor Cyan
}

function Write-Warn($Message) {
  Write-Host "[agent-installer] $Message" -ForegroundColor Yellow
}

function Add-UserPath($PathToAdd) {
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = @()
  if ($userPath) {
    $parts = $userPath -split ";" | Where-Object { $_ }
  }
  if ($parts -notcontains $PathToAdd) {
    $newPath = (@($PathToAdd) + $parts) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Step "Added PATH entry: $PathToAdd"
  }
  if (($env:Path -split ";") -notcontains $PathToAdd) {
    $env:Path = "$PathToAdd;$env:Path"
  }
}

function Invoke-External {
  param([string[]]$CommandAndArgs)
  $exe = $CommandAndArgs[0]
  $args = @()
  if ($CommandAndArgs.Length -gt 1) {
    $args = $CommandAndArgs[1..($CommandAndArgs.Length - 1)]
  }
  & $exe @args
}

function Get-NodePlatform {
  if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") {
    throw "Use install.sh on macOS or Linux."
  }

  switch ($env:PROCESSOR_ARCHITECTURE) {
    "ARM64" { return "win-arm64" }
    "AMD64" { return "win-x64" }
    default { throw "Unsupported CPU architecture: $env:PROCESSOR_ARCHITECTURE" }
  }
}

function Install-NodeFromMirror {
  New-Item -ItemType Directory -Force -Path $InstallHome | Out-Null
  $platform = Get-NodePlatform
  $sumsUrl = "$NodeMirror/$NodeChannel/SHASUMS256.txt"
  Write-Step "Downloading Node.js metadata from $sumsUrl"
  $sums = Invoke-RestMethod -Uri $sumsUrl
  $match = $sums -split "`n" | Where-Object { $_ -match "node-v.*-$platform\.zip$" } | Select-Object -First 1
  if (-not $match) {
    throw "Cannot find Node.js package for $platform from mirror."
  }

  $filename = ($match -split "\s+")[-1].Trim()
  $zipPath = Join-Path $env:TEMP $filename
  $extractPath = Join-Path $env:TEMP ([IO.Path]::GetFileNameWithoutExtension($filename))
  $url = "$NodeMirror/$NodeChannel/$filename"

  Write-Step "Downloading Node.js from $url"
  Invoke-WebRequest -Uri $url -OutFile $zipPath
  if (Test-Path $extractPath) {
    Remove-Item -Recurse -Force $extractPath
  }
  Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
  if (Test-Path $NodeHome) {
    Remove-Item -Recurse -Force $NodeHome
  }
  New-Item -ItemType Directory -Force -Path $NodeHome | Out-Null
  Copy-Item -Recurse -Force (Join-Path $extractPath "*") $NodeHome
}

function Ensure-Node {
  New-Item -ItemType Directory -Force -Path $NpmPrefix | Out-Null
  Add-UserPath $NpmPrefix
  Add-UserPath $NodeHome
  Add-UserPath $HermesScripts

  $node = Get-Command node -ErrorAction SilentlyContinue
  $npm = Get-Command npm -ErrorAction SilentlyContinue
  if ($node -and $npm) {
    Write-Step "Using existing Node.js: $(node -v)"
  } else {
    Install-NodeFromMirror
    Write-Step "Installed Node.js: $(& (Join-Path $NodeHome "node.exe") -v)"
  }

  npm config set registry $NpmRegistry | Out-Null
  npm config set prefix $NpmPrefix | Out-Null
}

function Get-PythonCommand {
  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    return @("py", "-3")
  }
  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    return @("python")
  }
  throw "Python 3 is required for hermes-agent. Install Python 3 first, then rerun this script."
}

function Invoke-Python {
  param([string[]]$Arguments)
  $cmd = Get-PythonCommand
  Invoke-External (@($cmd) + $Arguments)
}

function Invoke-HermesPython {
  param([string[]]$Arguments)
  & $HermesPython @Arguments
}

function Ensure-PythonAndPip {
  $cmd = Get-PythonCommand
  $version = Invoke-External (@($cmd) + @("--version"))
  Write-Step "Using Python: $version"
  if (-not (Test-Path $HermesPython)) {
    Invoke-Python @("-m", "venv", $HermesVenv)
  }
  Invoke-HermesPython @("-m", "ensurepip", "--upgrade") 2>$null
  Invoke-HermesPython @("-m", "pip", "--version") | Out-Null
  Invoke-HermesPython @("-m", "pip", "config", "set", "global.index-url", $PypiIndexUrl) | Out-Null
  Invoke-HermesPython @("-m", "pip", "config", "set", "global.trusted-host", $PypiTrustedHost) | Out-Null
}

function Install-NpmAgents {
  Write-Step "Installing OpenClaw, Codex, and Claude Code from $NpmRegistry"
  npm install -g openclaw@latest @openai/codex@latest @anthropic-ai/claude-code@latest --registry=$NpmRegistry
}

function Install-Hermes {
  Write-Step "Installing Hermes Agent from $PypiIndexUrl"
  Invoke-HermesPython @("-m", "pip", "install", "-U", "hermes-agent", "-i", $PypiIndexUrl, "--trusted-host", $PypiTrustedHost)
}

function Print-Versions {
  Write-Step "Installed command versions:"
  foreach ($command in @("openclaw", "codex", "claude")) {
    $found = Get-Command $command -ErrorAction SilentlyContinue
    if ($found) {
      & $command --version
    } else {
      Write-Warn "$command command is not available in current PATH."
    }
  }
  Invoke-HermesPython @("-m", "pip", "show", "hermes-agent")
}

Ensure-Node
Ensure-PythonAndPip
Install-NpmAgents
Install-Hermes
Print-Versions
Write-Step "Done. Open a new terminal if commands are not found immediately."
