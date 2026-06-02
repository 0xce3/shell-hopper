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

function Invoke-Wsl {
    param([string]$Command)
    wsl.exe -d $WslDistribution -- bash -lc $Command
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

function Install-NerdFont {
    param(
        [string]$Name,
        [string]$DownloadUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    )

    $fontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $markerFont = Join-Path $fontsDir "JetBrainsMonoNerdFont-Regular.ttf"

    if (Test-Path $markerFont) {
        Write-Host "$Name is already installed."
        return
    }

    Write-Host "Installing $Name..."
    New-Item -ItemType Directory -Force -Path $fontsDir | Out-Null

    $tempDir = Join-Path $env:TEMP "shellhopper-font-$([guid]::NewGuid().ToString())"
    $zipPath = Join-Path $tempDir "JetBrainsMono.zip"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        $fontFiles = Get-ChildItem $tempDir -Filter "*.ttf" -Recurse |
            Where-Object { $_.Name -like "JetBrainsMonoNerdFont*.ttf" }

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

    Write-Host "$Name installed."
}

function Install-WindowsTerminalProfile {
    $settingsPath = Get-WindowsTerminalSettingsPath
    if (-not $settingsPath) {
        Write-Host "Windows Terminal settings.json not found. Skipping profile creation."
        return
    }

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
    Write-Host "Windows Terminal profile installed: $ProfileName"
    Write-Host "Backup: $backupPath"
}

Write-Host "Preparing WSL distribution: $WslDistribution"

if (-not $SkipFontInstall) {
    Install-NerdFont -Name $FontFace
}

$bootstrap = @"
set -euo pipefail
repo_url='$RepoUrl'
mkdir -p ~/.local/bin ~/.config/shellhopper
curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/scripts/shellhopper.sh -o ~/.local/bin/shellhopper
chmod +x ~/.local/bin/shellhopper
if [ ! -f ~/.config/shellhopper/projects.tsv ]; then
  curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/templates/projects.tsv -o ~/.config/shellhopper/projects.tsv
fi
sudo apt-get update || true
sudo apt-get install -y curl git fzf jq neovim ripgrep fd-find tmux || {
  echo 'Optional package installation failed. ShellHopper itself is installed.'
  echo 'Install missing tools manually if selection or editor features are unavailable.'
}
if ! command -v docker >/dev/null 2>&1; then
  echo 'Docker CLI not found in WSL. ShellHopper will still work for WSL entries.'
  echo 'For container entries, install Docker Desktop WSL integration or a compatible Docker CLI.'
fi
if [ '$NvimConfigRepo' != '' ]; then
  if [ -d ~/.config/nvim/.git ]; then
    git -C ~/.config/nvim remote set-url origin '$NvimConfigRepo'
    git -C ~/.config/nvim pull --ff-only
  else
    if [ -e ~/.config/nvim ]; then
      mv ~/.config/nvim ~/.config/nvim.backup.`$(date +%Y%m%d%H%M%S)
    fi
    git clone '$NvimConfigRepo' ~/.config/nvim
  fi
  nvim --headless '+Lazy! sync' '+qa'
fi
echo 'ShellHopper installed.'
"@

Invoke-Wsl $bootstrap

if (-not $SkipWindowsTerminalProfile) {
    Install-WindowsTerminalProfile
}

Write-Host ""
Write-Host "Open Windows Terminal profile '$ProfileName' or run:"
Write-Host "  wsl.exe -d $WslDistribution -- bash -lc '~/.local/bin/shellhopper'"
