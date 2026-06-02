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

    $commandLine = "wsl.exe -d $WslDistribution -- bash -lc `"~/.local/bin/shellhopper`""
    $existing = $settings.profiles.list | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1

    if ($existing) {
        $existing.commandline = $commandLine
    } else {
        $profile = [pscustomobject]@{
            guid = "{$([guid]::NewGuid().ToString())}"
            name = $ProfileName
            commandline = $commandLine
            startingDirectory = "%USERPROFILE%"
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
sudo apt-get update
sudo apt-get install -y curl git fzf jq docker.io neovim ripgrep fd-find
mkdir -p ~/.local/bin ~/.config/shellhopper
tmp_dir=`$(mktemp -d)
git clone --depth=1 "`$repo_url" "`$tmp_dir/shell-hopper"
install -m 0755 "`$tmp_dir/shell-hopper/scripts/shellhopper.sh" ~/.local/bin/shellhopper
if [ ! -f ~/.config/shellhopper/projects.tsv ]; then
  cp "`$tmp_dir/shell-hopper/templates/projects.tsv" ~/.config/shellhopper/projects.tsv
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
rm -rf "`$tmp_dir"
echo 'ShellHopper installed.'
"@

Invoke-Wsl $bootstrap

if (-not $SkipWindowsTerminalProfile) {
    Install-WindowsTerminalProfile
}

Write-Host ""
Write-Host "Open Windows Terminal profile '$ProfileName' or run:"
Write-Host "  wsl.exe -d $WslDistribution -- bash -lc '~/.local/bin/shellhopper'"
