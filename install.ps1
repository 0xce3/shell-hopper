param(
    [string]$WslDistribution = "Ubuntu-22.04",
    [string]$ProfileName = "ShellHopper",
    [string]$RepoUrl = "https://github.com/0xce3/shell-hopper.git",
    [string]$NvimConfigRepo = "",
    [string]$FontFace = "JetBrainsMono Nerd Font",
    [string]$ProfileIcon = "⚡",
    [switch]$SkipFontInstall,
    [switch]$SkipWindowsTerminalProfile
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$script:InstallStep = 0
$script:InstallStepTotal = 4

function Install-Step {
    param([string]$Message)

    $script:InstallStep += 1
    Write-Host ""
    Write-Host "[$script:InstallStep/$script:InstallStepTotal] $Message"
}

function Install-Info {
    param([string]$Message)

    Write-Host "  - $Message"
}

function ConvertTo-ShellSingleQuoted {
    param([string]$Value)

    $quote = [string][char]39
    $escapedQuote = "$quote`"$quote`"$quote"
    return $quote + $Value.Replace($quote, $escapedQuote) + $quote
}

function Invoke-Wsl {
    param(
        [string]$Command,
        [string]$Description = "Running WSL command"
    )

    Install-Info "$Description in $WslDistribution"
    $Command | wsl.exe -d $WslDistribution -- bash -s
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed with exit code $LASTEXITCODE"
    }
}

function Get-WindowsTerminalSettingsPath {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Test-NerdFontInstalled {
    param([string]$Name)

    $fontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    if (Get-ChildItem $fontsDir -Filter "JetBrainsMonoNerdFont*.ttf" -ErrorAction SilentlyContinue) {
        return $true
    }

    $registryPaths = @(
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts",
        "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    )

    foreach ($registryPath in $registryPaths) {
        $fonts = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
        if (-not $fonts) {
            continue
        }

        foreach ($property in $fonts.PSObject.Properties) {
            if ($property.Name -like "*JetBrainsMono*Nerd*" -or $property.Value -like "*JetBrainsMono*Nerd*") {
                return $true
            }
        }
    }

    return $false
}

function Install-NerdFont {
    param(
        [string]$Name,
        [string]$DownloadUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    )

    $fontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"

    if (Test-NerdFontInstalled -Name $Name) {
        Install-Info "$Name is already installed"
        return
    }

    Install-Info "Downloading $Name"
    New-Item -ItemType Directory -Force -Path $fontsDir | Out-Null

    $tempDir = Join-Path $env:TEMP "shellhopper-font-$([guid]::NewGuid().ToString())"
    $zipPath = Join-Path $tempDir "JetBrainsMono.zip"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath
        Install-Info "Extracting font files"
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        $fontFiles = Get-ChildItem $tempDir -Filter "*.ttf" -Recurse |
            Where-Object { $_.Name -like "JetBrainsMonoNerdFont*.ttf" }

        Install-Info "Registering $($fontFiles.Count) font files for the current Windows user"
        foreach ($fontFile in $fontFiles) {
            $destination = Join-Path $fontsDir $fontFile.Name
            Copy-Item $fontFile.FullName $destination -Force

            $registryName = "$($fontFile.BaseName) (TrueType)"
            New-ItemProperty `
                -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" `
                -Name $registryName `
                -Value $destination `
                -PropertyType String `
                -Force | Out-Null
        }
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Install-Info "$Name installed"
}

function Install-WindowsTerminalProfile {
    $settingsPath = Get-WindowsTerminalSettingsPath
    if (-not $settingsPath) {
        Install-Info "Windows Terminal settings.json not found; skipping profile creation"
        return
    }

    Install-Info "Updating Windows Terminal profile '$ProfileName'"
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{ list = @() })
    }
    if (-not $settings.profiles.list) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name list -Value @()
    }

    $bootstrapCommand = "test -x ~/.local/bin/shellhopper || { mkdir -p ~/.local/bin ~/.config/shellhopper; curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/scripts/shellhopper.sh -o ~/.local/bin/shellhopper; chmod +x ~/.local/bin/shellhopper; test -f ~/.config/shellhopper/projects.tsv || curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/templates/projects.tsv -o ~/.config/shellhopper/projects.tsv; }; exec ~/.local/bin/shellhopper"
    $commandLine = "wsl.exe -d $WslDistribution -- bash -lc `"$bootstrapCommand`""
    $existing = $settings.profiles.list | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1

    if ($existing) {
        $existing.commandline = $commandLine
        if (-not $existing.font) {
            $existing | Add-Member -MemberType NoteProperty -Name font -Value ([pscustomobject]@{})
        }
        if (-not $existing.font.PSObject.Properties["face"]) {
            $existing.font | Add-Member -MemberType NoteProperty -Name face -Value $FontFace
        }
        $existing.font.face = $FontFace
        if (-not $existing.PSObject.Properties["icon"]) {
            $existing | Add-Member -MemberType NoteProperty -Name icon -Value $ProfileIcon
        }
        $existing.icon = $ProfileIcon
    } else {
        $profile = [pscustomobject]@{
            guid = "{$([guid]::NewGuid().ToString())}"
            name = $ProfileName
            commandline = $commandLine
            startingDirectory = "%USERPROFILE%"
            icon = $ProfileIcon
            font = [pscustomobject]@{
                face = $FontFace
            }
        }
        $settings.profiles.list += $profile
    }

    $backupPath = "$settingsPath.backup.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item $settingsPath $backupPath
    $settings | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 $settingsPath
    Install-Info "Windows Terminal profile installed: $ProfileName"
    Install-Info "Backup written to $backupPath"
}

Write-Host "ShellHopper installer"
Write-Host "Target WSL distribution: $WslDistribution"

if (-not $SkipFontInstall) {
    Install-Step "Install terminal font"
    Install-NerdFont -Name $FontFace
} else {
    Install-Step "Skip terminal font"
    Install-Info "Font installation skipped by parameter"
}

$bootstrap = @'
set -euo pipefail
repo_url=__REPO_URL__
nvim_config_repo=__NVIM_CONFIG_REPO__
say() { printf '\n%s\n' "[$1] $2"; }
info() { printf '  - %s\n' "$1"; }

say 1 'Installing ShellHopper launcher files'
mkdir -p ~/.local/bin ~/.config/shellhopper
curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/scripts/shellhopper.sh -o ~/.local/bin/shellhopper
chmod +x ~/.local/bin/shellhopper
info 'Installed ~/.local/bin/shellhopper'
if [ ! -f ~/.config/shellhopper/projects.tsv ]; then
  curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/templates/projects.tsv -o ~/.config/shellhopper/projects.tsv
  info 'Created ~/.config/shellhopper/projects.tsv'
else
  info 'Keeping existing ~/.config/shellhopper/projects.tsv'
fi

say 2 'Updating apt package index'
sudo apt-get update || true

say 3 'Installing WSL packages'
sudo apt-get install -y curl git fzf jq neovim ripgrep fd-find tmux || {
  echo 'Optional package installation failed. ShellHopper itself is installed.'
  echo 'Install missing tools manually if selection or editor features are unavailable.'
}

say 4 'Checking Docker CLI'
if ! command -v docker >/dev/null 2>&1; then
  echo 'Docker CLI not found in WSL. ShellHopper will still work for WSL entries.'
  echo 'For container entries, install Docker Desktop WSL integration or a compatible Docker CLI.'
else
  info 'Docker CLI found'
fi

if [ "$nvim_config_repo" != '' ]; then
  say 5 'Syncing Neovim config'
  if [ -d ~/.config/nvim/.git ]; then
    git -C ~/.config/nvim remote set-url origin "$nvim_config_repo"
    git -C ~/.config/nvim pull --ff-only
  else
    if [ -e ~/.config/nvim ]; then
      mv ~/.config/nvim ~/.config/nvim.backup.$(date +%Y%m%d%H%M%S)
    fi
    git clone "$nvim_config_repo" ~/.config/nvim
  fi
  nvim --headless '+Lazy! sync' '+qa'
else
  say 5 'Skipping Neovim config sync'
  info 'No -NvimConfigRepo parameter provided'
fi

say 6 'WSL setup complete'
'@

$bootstrap = $bootstrap.Replace("__REPO_URL__", (ConvertTo-ShellSingleQuoted $RepoUrl))
$bootstrap = $bootstrap.Replace("__NVIM_CONFIG_REPO__", (ConvertTo-ShellSingleQuoted $NvimConfigRepo))

Install-Step "Prepare WSL development tools"
Invoke-Wsl $bootstrap -Description "Installing ShellHopper files, packages, tmux, and optional Neovim config"

if (-not $SkipWindowsTerminalProfile) {
    Install-Step "Configure Windows Terminal profile"
    Install-WindowsTerminalProfile
} else {
    Install-Step "Skip Windows Terminal profile"
    Install-Info "Windows Terminal profile creation skipped by parameter"
}

Install-Step "Finish"
Install-Info "ShellHopper installed"
Install-Info "Open Windows Terminal profile '$ProfileName'"
Install-Info "Or run: wsl.exe -d $WslDistribution -- bash -lc '~/.local/bin/shellhopper'"
Write-Host ""
