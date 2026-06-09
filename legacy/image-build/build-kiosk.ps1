param(
    [switch]$CleanContainer
)

$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

Write-Host '[build-kiosk] Checking Docker daemon...'
try {
    docker info | Out-Null
} catch {
    throw "Docker daemon is not reachable. Start Docker Desktop, then retry."
}

if ($CleanContainer) {
    Write-Host '[build-kiosk] Removing stale pigen_work container (if present)...'
    docker rm -vf pigen_work | Out-Null
}

Write-Host '[build-kiosk] Starting kiosk image build...'
Write-Host '[build-kiosk] Command: bash ./build.sh --docker'
bash ./build.sh --docker

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Write-Host '[build-kiosk] Build completed successfully.'
