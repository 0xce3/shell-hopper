$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repo = "0xce3/shell-hopper"
$ref = "main"
$installerPath = Join-Path $env:TEMP "shellhopper-install.ps1"
$commitUrl = "https://api.github.com/repos/$repo/commits/$ref"
$logPath = Join-Path $env:TEMP "shellhopper-bootstrap.log"
$headers = @{
    "Cache-Control" = "no-cache"
    "Pragma" = "no-cache"
}

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
    Write-Host "  - Resolving latest commit for $repo@$ref"

    $commit = Invoke-RestMethod -Uri $commitUrl -Headers $headers
    $sha = $commit.sha
    if (-not $sha) {
        throw "Could not resolve latest commit for $repo@$ref"
    }

    $installerUrl = "https://api.github.com/repos/$repo/contents/install.ps1?ref=$sha"
    Write-Host "  - Downloading installer from commit $($sha.Substring(0, 7))"

    $installer = Invoke-RestMethod -Uri $installerUrl -Headers $headers
    $content = [Convert]::FromBase64String(($installer.content -replace "\s", ""))
    [IO.File]::WriteAllBytes($installerPath, $content)

    $installerText = [Text.Encoding]::UTF8.GetString($content)
    if (-not $installerText.Contains('$bootstrap = @''')) {
        throw "Downloaded installer did not contain the expected WSL quoting fix"
    }

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
