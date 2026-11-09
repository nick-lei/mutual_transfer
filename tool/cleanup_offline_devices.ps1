param(
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'NearLink'),
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$DataDirectory = (Resolve-Path -LiteralPath $DataDirectory).Path
$settingsPath = Join-Path $DataDirectory 'settings.json'
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw 'No NearLink settings file exists in the requested data directory.'
}
$lockPath = Join-Path $DataDirectory '.instance.lock'
$lockStream = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'ReadWrite')
$locked = $false
$temporary = $null
try {
    # Use the same byte-range lock as LanService; never edit a running profile.
    $lockStream.Lock(0, 1)
    $locked = $true
    $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsPath | ConvertFrom-Json
    if (-not $config.id -or -not $config.PSObject.Properties['peers']) {
        throw 'Invalid NearLink settings. No changes were made.'
    }
    $referenced = [System.Collections.Generic.HashSet[string]]::new()
    $historyPath = Join-Path $DataDirectory 'history.json'
    if (Test-Path -LiteralPath $historyPath) {
        $history = Get-Content -Raw -Encoding UTF8 -LiteralPath $historyPath | ConvertFrom-Json
        if (-not $history.PSObject.Properties['messages'] -or
            -not $history.PSObject.Properties['transfers']) {
            throw 'Invalid NearLink history. No changes were made.'
        }
        foreach ($record in @($history.messages) + @($history.transfers)) {
            if ($record.peerId) { [void]$referenced.Add($record.peerId) }
        }
    }
    foreach ($group in @($config.groups)) {
        if (-not $group) { continue }
        if ($group.ownerId) { [void]$referenced.Add($group.ownerId) }
        foreach ($member in @($group.members)) {
            if ($member.id) { [void]$referenced.Add($member.id) }
        }
        foreach ($peerId in @($group.pendingSync)) {
            if ($peerId) { [void]$referenced.Add($peerId) }
        }
    }
    $before = @($config.peers)
    $removable = @($before | Where-Object {
        $_.id -and $_.id -ne $config.id -and -not $_.manual -and
        -not $_.remark -and -not $referenced.Contains($_.id)
    })
    $backupPath = $null
    if ($Apply -and $removable.Count -gt 0) {
        $backups = Join-Path $DataDirectory 'backups'
        New-Item -ItemType Directory -Path $backups -Force | Out-Null
        $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
        $backupPath = Join-Path $backups "devices-before-cleanup-$stamp.json"
        Copy-Item -LiteralPath $settingsPath -Destination $backupPath
        $ids = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($peer in $removable) { [void]$ids.Add($peer.id) }
        $config.peers = @($before | Where-Object { -not $ids.Contains($_.id) })
        $temporary = Join-Path $DataDirectory "settings-cleanup-$stamp.tmp"
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($temporary,
            ($config | ConvertTo-Json -Depth 100 -Compress), $utf8)
        [System.IO.File]::Replace($temporary, $settingsPath, $backupPath)
        $temporary = $null
    }
    [pscustomobject]@{
        DataDirectory = $DataDirectory
        Applied = [bool]$Apply
        Before = $before.Count
        Eligible = $removable.Count
        Removed = $(if ($Apply) { $removable.Count } else { 0 })
        Backup = $backupPath
    } | ConvertTo-Json
} finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) {
        Remove-Item -LiteralPath $temporary
    }
    if ($locked) { $lockStream.Unlock(0, 1) }
    $lockStream.Dispose()
}
