param(
    [Parameter(Mandatory = $true)]
    [string]$BaseImage,
    [string]$OutputImage
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

if (!(Test-Path -LiteralPath $BaseImage)) {
    throw "Base image not found: $BaseImage"
}

$baseResolved = (Resolve-Path -LiteralPath $BaseImage).Path
$baseWsl = (wsl wslpath -a "$baseResolved").Trim()

if ([string]::IsNullOrWhiteSpace($OutputImage)) {
    $outWsl = ''
} else {
    $outputFull = [System.IO.Path]::GetFullPath((Join-Path $PWD $OutputImage))
    $outWsl = (wsl wslpath -a "$outputFull").Trim()
}

$repoWsl = (wsl wslpath -a "$PSScriptRoot").Trim()

if ([string]::IsNullOrWhiteSpace($outWsl)) {
    $cmd = "cd '$repoWsl' && bash ./quick-build.sh '$baseWsl'"
} else {
    $cmd = "cd '$repoWsl' && bash ./quick-build.sh '$baseWsl' '$outWsl'"
}

Write-Host "[quick-build] Running in WSL: $cmd"
wsl -e bash -lc $cmd

if ($LASTEXITCODE -ne 0) {
    throw "quick-build failed with exit code $LASTEXITCODE"
}
