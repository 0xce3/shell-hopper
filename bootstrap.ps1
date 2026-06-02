$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repo = "0xce3/shell-hopper"
$ref = "main"
$installerPath = Join-Path $env:TEMP "shellhopper-install.ps1"
$installerUrl = "https://api.github.com/repos/$repo/contents/install.ps1?ref=$ref"
$logPath = Join-Path $env:TEMP "shellhopper-bootstrap.log"

function Wait-OnFailure {
    param([string]$Message)

    Write-Host ""
    Write-Host "ShellHopper installation failed."
    Write-Host "  - $Message"
    Write-Host "  - Log: $logPath"

    if ([Environment]::UserInteractive) {
        Read-Host "Press Enter to close this window"
    }
}

try {
    Start-Transcript -Path $logPath -Force | Out-Null

    Write-Host "ShellHopper bootstrap"
    Write-Host "  - Log: $logPath"
    Write-Host "  - Downloading latest installer from $repo@$ref"

    $installer = Invoke-RestMethod -Uri $installerUrl
    $content = [Convert]::FromBase64String(($installer.content -replace "\s", ""))
    [IO.File]::WriteAllBytes($installerPath, $content)

    Write-Host "  - Running installer"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath

    if ($LASTEXITCODE -ne 0) {
        throw "Installer exited with code $LASTEXITCODE"
    }
} catch {
    Wait-OnFailure -Message $_.Exception.Message
    exit 1
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
