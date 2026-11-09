param([string]$Version = '0.2.5')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$productionSetup = Join-Path $projectRoot "outputs\NearLink-$Version-windows-x64-Setup.exe"
$payload = Join-Path $projectRoot "outputs\NearLink-$Version-windows-x64"
$verificationRoot = Join-Path $projectRoot 'build\installer-verification'
$chineseName = [string][char]0x90BB + [char]0x4F20
$destination = Join-Path $verificationRoot "$chineseName install"
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E044D4B3-E77B-46C0-B71B-6A54A097D770}_is1'
$runKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
$approvedKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$verificationName = 'NearLink Installer Verification'
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) "$verificationName.lnk"
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'NearLinkInstallerVerification'
if ((Test-Path -LiteralPath $uninstallKey) -or (Test-Path -LiteralPath $desktopLink) -or (Test-Path -LiteralPath $startMenu)) {
    throw 'An existing NearLink installation or shortcut is present; verification will not overwrite it.'
}
if (-not (Test-Path -LiteralPath $productionSetup)) { throw 'Build the installer first.' }
foreach ($running in Get-CimInstance Win32_Process -Filter "Name='mutual_transfer.exe'") {
    if ($running.ExecutablePath) { throw 'Exit all NearLink applications before running installer verification.' }
}
if (-not [IO.Path]::GetFullPath($destination).StartsWith([IO.Path]::GetFullPath((Join-Path $projectRoot 'build')) + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Verification directory must stay within this project build directory.'
}
New-Item -ItemType Directory -Path $verificationRoot -Force | Out-Null
$compiler = Join-Path $projectRoot 'build\installer-tools\inno-7.1.1\ISCC.exe'
& $compiler '/Qp' "/DAppVersion=$Version" "/DPackageDirectory=$payload" "/DOutputDirectory=$verificationRoot" "/DAppName=$verificationName" '/DAppMenuName=NearLinkInstallerVerification' '/DAppGuid={E044D4B3-E77B-46C0-B71B-6A54A097D770}' (Join-Path $projectRoot 'windows\installer\nearlink.iss')
if ($LASTEXITCODE -ne 0) { throw 'Isolated installer compilation failed.' }
$setup = Join-Path $verificationRoot "NearLink-$Version-windows-x64-Setup.exe"
$checks = [Collections.Generic.List[string]]::new()
$testProcesses = [Collections.Generic.List[int]]::new()
function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $checks.Add($Message)
    Write-Output "PASS $Message"
}
function Execute([string]$File, [string[]]$Arguments) {
    $process = Start-Process -FilePath $File -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
    try { return $process.ExitCode }
    finally { $process.Dispose() }
}
function IsRunning([int]$ProcessId) {
    return [bool](Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId")
}
function LaunchFixture([string]$Executable, [string]$ProfileName) {
    $profile = Join-Path $verificationRoot ($ProfileName + '-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $profile -Force | Out-Null
    @{ sidebarCollapsed = $true; closeToTray = $true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profile 'desktop.json') -Encoding UTF8
    @{ modifiers = 3; key = 65; enabled = $false; hideWindowOnCapture = $true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profile 'screenshot.json') -Encoding UTF8
    $process = Start-Process -FilePath $Executable -ArgumentList @("--data-dir=`"$profile`"", '--no-discovery', '--no-notifications', '--autostart') -WorkingDirectory (Split-Path -Parent $Executable) -WindowStyle Hidden -PassThru
    $fixtureId = $process.Id
    $process.Dispose()
    $testProcesses.Add($fixtureId)
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        if (-not (IsRunning $fixtureId)) { throw 'Fixture application exited unexpectedly.' }
        $logPath = Join-Path $profile 'logs\nearlink.jsonl'
        if ((Test-Path -LiteralPath $logPath) -and (Get-Content -LiteralPath $logPath -Raw) -match 'service_started') {
            return @{ Id = $fixtureId; Log = $logPath; Profile = $profile }
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'Fixture application did not finish startup.'
}
function SaveRegistryValue([string]$Path) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    try {
        if ($key -and $key.GetValueNames() -contains 'NearLink') {
            return @{ Exists = $true; Value = $key.GetValue('NearLink'); Kind = $key.GetValueKind('NearLink') }
        }
        return @{ Exists = $false }
    } finally { if ($key) { $key.Dispose() } }
}
function SetStartup([string]$Value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($runKey)
    try { $key.SetValue('NearLink', $Value, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $key.Dispose() }
}
function RestoreRegistryValue([string]$Path, [hashtable]$Saved) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
    try {
        if ($Saved.Exists) { $key.SetValue('NearLink', $Saved.Value, $Saved.Kind) }
        else { $key.DeleteValue('NearLink', $false) }
    } finally { $key.Dispose() }
}
$savedRun = SaveRegistryValue $runKey
$savedApproval = SaveRegistryValue $approvedKey
$dataFiles = @{}
foreach ($name in @('settings.json', 'history.json', 'desktop.json', 'screenshot.json')) {
    $path = Join-Path $env:LOCALAPPDATA "NearLink\$name"
    if (Test-Path -LiteralPath $path) { $dataFiles[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$installArguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/LANG=chinesesimplified', '/TASKS=desktopicon', "/DIR=`"$destination`"")
$uninstaller = Join-Path $destination 'unins000.exe'
$resultPath = Join-Path $verificationRoot 'result.json'
try {
    $code = Execute $setup ($installArguments + "/LOG=`"$(Join-Path $verificationRoot 'install.log')`"")
    Check ($code -eq 0) 'First installation completed'
    Check (Test-Path -LiteralPath $uninstallKey) 'Current-user uninstall registration exists'
    $registration = Get-ItemProperty -LiteralPath $uninstallKey
    Check ($registration.DisplayVersion -eq $Version) 'Installed version matches payload'
    Check ([IO.Path]::GetFullPath($registration.InstallLocation).TrimEnd('\') -eq [IO.Path]::GetFullPath($destination)) 'Selected Unicode installation directory is respected'
    foreach ($file in Get-ChildItem -LiteralPath $payload -Recurse -File) {
        $relative = $file.FullName.Substring($payload.Length).TrimStart('\')
        $installedFile = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $installedFile) -or (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) {
            throw "Installed payload mismatch: $relative"
        }
    }
    Check $true 'All installed payload files match their source hashes'
    $shell = New-Object -ComObject WScript.Shell
    Check (Test-Path -LiteralPath $desktopLink) 'Desktop shortcut exists'
    Check ($shell.CreateShortcut($desktopLink).TargetPath -eq (Join-Path $destination 'mutual_transfer.exe')) 'Desktop shortcut targets the installed executable'
    Check (Test-Path -LiteralPath (Join-Path $startMenu "$verificationName.lnk")) 'Start menu shortcut exists'
    Check (-not (SaveRegistryValue $runKey).Exists -or $savedRun.Exists) 'First install does not opt into startup'

    $guard = [Threading.Mutex]::new($false, 'Local\NearLink.InstallationGuard')
    try {
        $code = Execute $setup ($installArguments + "/LOG=`"$(Join-Path $verificationRoot 'blocked-upgrade.log')`"")
        Check ($code -ne 0) 'Running-app mutex blocks installation'
        $code = Execute $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$(Join-Path $verificationRoot 'blocked-uninstall.log')`"")
        Check ($code -ne 0 -and (Test-Path -LiteralPath $uninstaller)) 'Running-app mutex blocks uninstall'
        $code = Execute $setup ($installArguments + '/FORCECLOSENEARLINK=1')
        Check ($code -ne 0) 'Force-close never bypasses an unreleased installation guard'
    } finally { $guard.Dispose() }

    $fixture = LaunchFixture (Join-Path $destination 'mutual_transfer.exe') 'normal-exit'
    $code = Execute $setup ($installArguments + ('/LOG="' + (Join-Path $verificationRoot 'no-consent.log') + '"'))
    Check ($code -ne 0 -and (IsRunning $fixture.Id)) 'Silent setup does not stop a running app without explicit opt-in'
    $code = Execute $setup ($installArguments + @('/FORCECLOSENEARLINK=1', ('/LOG="' + (Join-Path $verificationRoot 'normal-exit.log') + '"')))
    Check ($code -eq 0 -and -not (IsRunning $fixture.Id)) 'Setup closes a tray instance and continues installation'
    $runtimeLog = Get-Content -LiteralPath $fixture.Log -Raw
    Check ($runtimeLog -match 'exit_for_update' -and $runtimeLog -match 'service_stopped') 'New application exits through normal persisted cleanup'
    Check ((Get-Content -LiteralPath (Join-Path $fixture.Profile 'desktop.json') -Raw | ConvertFrom-Json).closeToTray) 'Installer exit does not change the close-to-tray preference'

    $legacy = Join-Path $projectRoot 'outputs\NearLink-0.1.0-windows-x64\mutual_transfer.exe'
    if (-not (Test-Path -LiteralPath $legacy)) { throw 'Legacy 0.1.0 payload is required for compatibility verification.' }
    $fixture = LaunchFixture $legacy 'legacy-force-exit'
    $unrelatedDirectory = Join-Path $verificationRoot 'unrelated'
    New-Item -ItemType Directory -Path $unrelatedDirectory -Force | Out-Null
    $unrelatedExecutable = Join-Path $unrelatedDirectory 'mutual_transfer.exe'
    Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\ping.exe') -Destination $unrelatedExecutable -Force
    $unrelated = Start-Process -FilePath $unrelatedExecutable -ArgumentList @('-t','127.0.0.1') -WindowStyle Hidden -PassThru
    $testProcesses.Add($unrelated.Id)
    $unrelatedId = $unrelated.Id
    $unrelated.Dispose()
    $code = Execute $setup ($installArguments + @('/FORCECLOSENEARLINK=1', ('/LOG="' + (Join-Path $verificationRoot 'legacy-force-exit.log') + '"')))
    Check ($code -eq 0 -and -not (IsRunning $fixture.Id)) 'Setup force closes a legacy application without the exit endpoint'
    Check ((Get-Content -LiteralPath (Join-Path $verificationRoot 'legacy-force-exit.log') -Raw) -match 'Forced NearLink exit:.*result 0') 'Legacy termination is confirmed in the setup log'
    Check (IsRunning $unrelatedId) 'An unrelated program with the same executable name is preserved'

    SetStartup '"C:\NearLink Previous\mutual_transfer.exe" --autostart'
    $code = Execute $setup ($installArguments + "/LOG=`"$(Join-Path $verificationRoot 'upgrade.log')`"")
    Check ($code -eq 0) 'In-place upgrade completed'
    $expectedStartup = '"' + (Join-Path $destination 'mutual_transfer.exe') + '" --autostart'
    Check ((SaveRegistryValue $runKey).Value -eq $expectedStartup) 'Upgrade migrates the existing startup path'
    $fixture = LaunchFixture (Join-Path $destination 'mutual_transfer.exe') 'uninstall-exit'
    $code = Execute $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    Check ($code -ne 0 -and (IsRunning $fixture.Id)) 'Silent uninstall requires explicit shutdown opt-in'
    $code = Execute $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/FORCECLOSENEARLINK=1', "/LOG=`"$(Join-Path $verificationRoot 'uninstall.log')`"")
    Check (-not (IsRunning $fixture.Id)) 'Uninstall closes the running application'
    Check ($code -eq 0) 'Uninstall completed'
    Check (-not (Test-Path -LiteralPath $uninstallKey)) 'Uninstall registration was removed'
    Check (-not (Test-Path -LiteralPath (Join-Path $destination 'mutual_transfer.exe'))) 'Installed executable was removed'
    Check (-not (Test-Path -LiteralPath $desktopLink)) 'Desktop shortcut was removed'
    Check (-not (SaveRegistryValue $runKey).Exists) 'Owned startup entry was removed'

    $code = Execute $setup ($installArguments + "/LOG=`"$(Join-Path $verificationRoot 'reinstall.log')`"")
    Check ($code -eq 0) 'Clean reinstall completed'
    $portableStartup = '"C:\NearLink Portable\mutual_transfer.exe" --autostart'
    SetStartup $portableStartup
    $fixture = LaunchFixture $legacy 'legacy-uninstall-exit'
    $code = Execute $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/FORCECLOSENEARLINK=1', "/LOG=`"$(Join-Path $verificationRoot 'portable-startup-uninstall.log')`"")
    Check (-not (IsRunning $fixture.Id)) 'Uninstall can force close a legacy tray instance'
    Check ($code -eq 0) 'Second uninstall completed'
    Check ((SaveRegistryValue $runKey).Value -eq $portableStartup) 'Uninstall preserves a startup entry owned by a portable copy'
    foreach ($path in $dataFiles.Keys) {
        Check ((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $dataFiles[$path]) "User data preserved: $([IO.Path]::GetFileName($path))"
    }
    @{ time = (Get-Date).ToUniversalTime().ToString('o'); installer = $productionSetup; isolatedInstaller = $setup; checks = $checks; passed = $true } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $resultPath -Encoding UTF8
} finally {
    foreach ($testId in $testProcesses) {
        $remaining = Get-CimInstance Win32_Process -Filter "ProcessId=$testId"
        if ($remaining -and $remaining.ExecutablePath -and
            ($remaining.ExecutablePath.StartsWith($verificationRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
             $remaining.ExecutablePath.StartsWith((Join-Path $projectRoot 'outputs') + '\', [StringComparison]::OrdinalIgnoreCase))) {
            $null = Invoke-CimMethod -InputObject $remaining -MethodName Terminate -Arguments @{Reason=[uint32]0}
        }
    }
    if (Test-Path -LiteralPath $uninstaller) {
        $null = Execute $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    }
    RestoreRegistryValue $runKey $savedRun
    RestoreRegistryValue $approvedKey $savedApproval
}
Write-Output $resultPath
