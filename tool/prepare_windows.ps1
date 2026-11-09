$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$metadataPath = Join-Path $projectRoot '.flutter-plugins-dependencies'
if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw 'Run flutter pub get first.'
}
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$linksRoot = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $linksRoot -Force | Out-Null
foreach ($plugin in $metadata.plugins.windows) {
    $linkPath = Join-Path $linksRoot $plugin.name
    if (Test-Path -LiteralPath $linkPath) {
        $existing = Get-Item -LiteralPath $linkPath
        $expected = [IO.Path]::GetFullPath($plugin.path).TrimEnd('\')
        if ($existing.LinkType -and [IO.Path]::GetFullPath([string]$existing.Target).TrimEnd('\') -ne $expected) {
            Remove-Item -LiteralPath $linkPath -Force
        }
    }
    if (-not (Test-Path -LiteralPath $linkPath)) {
        New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
    }
}
Write-Output 'Windows plugin junctions are ready.'
