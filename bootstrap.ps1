$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repo = "0xce3/shell-hopper"
$ref = "main"
$installerPath = Join-Path $env:TEMP "shellhopper-install.ps1"
$installerUrl = "https://api.github.com/repos/$repo/contents/install.ps1?ref=$ref"

Write-Host "ShellHopper bootstrap"
Write-Host "  - Downloading latest installer from $repo@$ref"

$installer = Invoke-RestMethod -Uri $installerUrl
$content = [Convert]::FromBase64String(($installer.content -replace "\s", ""))
[IO.File]::WriteAllBytes($installerPath, $content)

Write-Host "  - Running installer"
& powershell -ExecutionPolicy Bypass -File $installerPath

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
