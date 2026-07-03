$ErrorActionPreference = "Stop"

$NpmRegistry = if ($env:NPM_REGISTRY) { $env:NPM_REGISTRY } else { "https://registry.npmmirror.com" }
$PypiIndexUrl = if ($env:PYPI_INDEX_URL) { $env:PYPI_INDEX_URL } else { "https://pypi.tuna.tsinghua.edu.cn/simple" }
$PypiTrustedHost = if ($env:PYPI_TRUSTED_HOST) { $env:PYPI_TRUSTED_HOST } else { "pypi.tuna.tsinghua.edu.cn" }
$NodeMirror = if ($env:NODE_MIRROR) { $env:NODE_MIRROR.TrimEnd("/") } else { "https://npmmirror.com/mirrors/node" }
$NodeChannel = if ($env:NODE_CHANNEL) { $env:NODE_CHANNEL } else { "latest-v22.x" }
$PythonMirror = if ($env:PYTHON_MIRROR) { $env:PYTHON_MIRROR.TrimEnd("/") } else { "https://registry.npmmirror.com/-/binary/python" }
$PythonVersion = if ($env:PYTHON_VERSION) { $env:PYTHON_VERSION } else { "3.12.10" }
$InstallHome = if ($env:AGENT_INSTALLER_HOME) { $env:AGENT_INSTALLER_HOME } else { Join-Path $env:USERPROFILE ".agent-installer" }
$NodeHome = Join-Path $InstallHome "node"
$NpmPrefix = Join-Path $InstallHome "npm-global"
$PythonHome = Join-Path $InstallHome "python"
$HermesVenv = Join-Path $InstallHome "hermes-venv"
$HermesScripts = Join-Path $HermesVenv "Scripts"
$HermesPython = Join-Path $HermesScripts "python.exe"
$NodeExe = Join-Path $NodeHome "node.exe"
$NpmCmd = Join-Path $NodeHome "npm.cmd"
$PythonExe = Join-Path $PythonHome "python.exe"

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

function Invoke-Checked {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$Action
  )
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Action failed with exit code $LASTEXITCODE."
  }
}

function Get-NpmCmd {
  if (Test-Path $NpmCmd) {
    return $NpmCmd
  }
  $found = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($found) {
    return $found.Source
  }
  throw "npm.cmd is not available. Node.js installation may be incomplete."
}

function Get-CommandCmd {
  param([string]$Name)
  $local = Join-Path $NpmPrefix "$Name.cmd"
  if (Test-Path $local) {
    return $local
  }
  $found = Get-Command "$Name.cmd" -ErrorAction SilentlyContinue
  if ($found) {
    return $found.Source
  }
  return $null
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
    Write-Step "Installed Node.js: $(& $NodeExe -v)"
  }

  $npm = Get-NpmCmd
  Invoke-Checked -FilePath $npm -Arguments @("config", "set", "registry", $NpmRegistry) -Action "Configure npm registry"
  Invoke-Checked -FilePath $npm -Arguments @("config", "set", "prefix", $NpmPrefix) -Action "Configure npm prefix"
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
  if (Test-Path $PythonExe) {
    return @($PythonExe)
  }
  return $null
}

function Get-PythonArch {
  switch ($env:PROCESSOR_ARCHITECTURE) {
    "ARM64" { return "arm64" }
    "AMD64" { return "amd64" }
    default { throw "Unsupported CPU architecture for Python: $env:PROCESSOR_ARCHITECTURE" }
  }
}

function Install-PythonFromMirror {
  New-Item -ItemType Directory -Force -Path $InstallHome | Out-Null
  $arch = Get-PythonArch
  $filename = "python-$PythonVersion-$arch.exe"
  $url = "$PythonMirror/$PythonVersion/$filename"
  $installerPath = Join-Path $env:TEMP $filename

  Write-Step "Downloading Python from $url"
  Invoke-WebRequest -Uri $url -OutFile $installerPath

  if (Test-Path $PythonHome) {
    Remove-Item -Recurse -Force $PythonHome
  }

  Write-Step "Installing Python $PythonVersion to $PythonHome (per-user, silent)"
  $installArgs = "/quiet InstallAllUsers=0 `"TargetDir=$PythonHome`" PrependPath=0 Include_launcher=0 Include_test=0 Include_pip=1 CompileAll=0"
  $proc = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
  Remove-Item -Force $installerPath -ErrorAction SilentlyContinue
  if ($proc.ExitCode -ne 0) {
    throw "Python installer failed with exit code $($proc.ExitCode)."
  }
  if (-not (Test-Path $PythonExe)) {
    throw "Python installation to $PythonHome did not produce python.exe."
  }
}

function Invoke-Python {
  param([string[]]$Arguments)
  $cmd = Get-PythonCommand
  Invoke-External (@($cmd) + $Arguments)
}

function Invoke-HermesPython {
  param([string[]]$Arguments)
  Invoke-Checked -FilePath $HermesPython -Arguments $Arguments -Action "Run Hermes Python"
}

function Ensure-PythonAndPip {
  $cmd = Get-PythonCommand
  if (-not $cmd) {
    Write-Step "Python 3 not found. Downloading from mirror."
    Install-PythonFromMirror
    Add-UserPath $PythonHome
    $cmd = Get-PythonCommand
    if (-not $cmd) {
      throw "Python installation from mirror did not produce a usable python command."
    }
  }
  $version = Invoke-External (@($cmd) + @("--version"))
  Write-Step "Using Python: $version"
  if (-not (Test-Path $HermesPython)) {
    Invoke-Python @("-m", "venv", $HermesVenv)
    if (-not (Test-Path $HermesPython)) {
      throw "Create Hermes Python virtual environment failed."
    }
  }
  Invoke-HermesPython @("-m", "ensurepip", "--upgrade") 2>$null
  Invoke-HermesPython @("-m", "pip", "--version") | Out-Null
  Invoke-HermesPython @("-m", "pip", "config", "set", "global.index-url", $PypiIndexUrl) | Out-Null
  Invoke-HermesPython @("-m", "pip", "config", "set", "global.trusted-host", $PypiTrustedHost) | Out-Null
}

function Install-NpmAgents {
  Write-Step "Installing OpenClaw, Codex, and Claude Code from $NpmRegistry"
  $npm = Get-NpmCmd
  Invoke-Checked -FilePath $npm -Arguments @("install", "-g", "openclaw@latest", "@openai/codex@latest", "@anthropic-ai/claude-code@latest", "--registry=$NpmRegistry") -Action "Install npm agents"
}

function Install-Hermes {
  Write-Step "Installing Hermes Agent from $PypiIndexUrl"
  Invoke-HermesPython @("-m", "pip", "install", "-U", "hermes-agent", "-i", $PypiIndexUrl, "--trusted-host", $PypiTrustedHost)
}

function Print-Versions {
  Write-Step "Installed command versions:"
  foreach ($command in @("openclaw", "codex", "claude")) {
    $found = Get-CommandCmd $command
    if ($found) {
      & $found --version
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
