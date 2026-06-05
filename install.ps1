param(
    [string]$WslDistribution = "Ubuntu-22.04",
    [string]$ProfileName = "ShellHopper",
    [string]$RepoUrl = "https://github.com/0xce3/shell-hopper.git",
    [string]$NvimConfigRepo = "",
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

    $bootstrapCommand = "mkdir -p ~/.local/bin ~/.config/shellhopper; curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/scripts/shellhopper.sh -o ~/.local/bin/shellhopper.tmp && mv ~/.local/bin/shellhopper.tmp ~/.local/bin/shellhopper && chmod +x ~/.local/bin/shellhopper; curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/scripts/shellhopper-sim-bridge -o ~/.local/bin/shellhopper-sim-bridge && chmod +x ~/.local/bin/shellhopper-sim-bridge; test -f ~/.config/shellhopper/projects.tsv || curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/templates/projects.tsv -o ~/.config/shellhopper/projects.tsv; exec ~/.local/bin/shellhopper"
    $commandLine = "wsl.exe -d $WslDistribution -- bash -lc `"$bootstrapCommand`""
    $existing = $settings.profiles.list | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1

    if ($existing) {
        $existing.commandline = $commandLine
        $existing.startingDirectory = "%USERPROFILE%"
        if (-not $existing.PSObject.Properties["scrollbarState"]) {
            $existing | Add-Member -MemberType NoteProperty -Name scrollbarState -Value "hidden"
        }
        $existing.scrollbarState = "hidden"
        if ($existing.PSObject.Properties["icon"]) {
            $existing.PSObject.Properties.Remove("icon")
        }
    } else {
        $profile = [pscustomobject]@{
            guid = "{$([guid]::NewGuid().ToString())}"
            name = $ProfileName
            commandline = $commandLine
            startingDirectory = "%USERPROFILE%"
            scrollbarState = "hidden"
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

$bootstrap = @"
set -euo pipefail
repo_url='$RepoUrl'
mkdir -p ~/.local/bin ~/.config/shellhopper
curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/scripts/shellhopper.sh -o ~/.local/bin/shellhopper
curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/scripts/shellhopper-sim-bridge -o ~/.local/bin/shellhopper-sim-bridge
chmod +x ~/.local/bin/shellhopper ~/.local/bin/shellhopper-sim-bridge
if [ ! -f ~/.config/shellhopper/projects.tsv ]; then
  curl -fsSL https://raw.githubusercontent.com/0xce3/shell-hopper/main/templates/projects.tsv -o ~/.config/shellhopper/projects.tsv
fi
mkdir -p ~/.config/tmux ~/.config/shellhopper
cat > ~/.config/tmux/tmux.conf <<'SHELLHOPPER_TMUX'
set -g default-terminal "tmux-256color"
set -g terminal-overrides ",*:RGB"
set -g terminal-features "*:RGB"
set -g status-style "bg=#32302f,fg=#ebdbb2"
set -g window-status-current-style "bg=#504945,fg=#fabd2f,bold"
set -g window-status-style "bg=#32302f,fg=#a89984"
SHELLHOPPER_TMUX
cp ~/.config/tmux/tmux.conf ~/.config/shellhopper/tmux.conf
if command -v tmux >/dev/null 2>&1; then
  tmux source-file ~/.config/tmux/tmux.conf >/dev/null 2>&1 || true
fi
sudo apt-get update || true
sudo apt-get install -y curl git fzf jq neovim ripgrep fd-find tmux tio || {
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
