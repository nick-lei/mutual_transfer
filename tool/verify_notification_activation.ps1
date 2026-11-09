param(
    [ValidateSet('open','accept','reject')][string]$Action = 'open'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$profileLog = Join-Path $projectRoot 'build/notification-verification/receiver/logs/nearlink.jsonl'
$events = Get-Content -LiteralPath $profileLog | ForEach-Object { $_ | ConvertFrom-Json }
$offer = $events | Where-Object { $_.event -eq 'offer_received' } | Select-Object -Last 1
if (-not $offer -or (Get-Date).ToUniversalTime() - [DateTime]$offer.time -gt [TimeSpan]::FromMinutes(1)) {
    throw 'Start a fresh isolated notification sender before testing activation.'
}
$profileDirectory = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build/notification-verification/receiver')).ToLowerInvariant()
$hasher = [Security.Cryptography.SHA256]::Create()
try { $digest = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($profileDirectory))).Replace('-','').ToLowerInvariant() }
finally { $hasher.Dispose() }
$appId = 'NearLink.Profile.' + $digest.Substring(0,16)
$registration = Get-ItemProperty (Join-Path 'HKCU:/Software/Classes/AppUserModelId' $appId)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("53E31837-6600-4A81-9395-75CFFE746F94"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface INearLinkTestActivation {
    [PreserveSig] int Activate([MarshalAs(UnmanagedType.LPWStr)] string appId,
        [MarshalAs(UnmanagedType.LPWStr)] string arguments, IntPtr data, uint count);
}
public static class NearLinkTestActivation {
    public static int Invoke(string classId, string appId, string arguments) {
        object target = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid(classId)));
        try { return ((INearLinkTestActivation)target).Activate(appId, arguments, IntPtr.Zero, 0); }
        finally { Marshal.ReleaseComObject(target); }
    }
}
'@
$payload = @{id=$offer.fields.offerId;action=$Action} | ConvertTo-Json -Compress
$code = [NearLinkTestActivation]::Invoke($registration.CustomActivator, $registration.PSChildName, $payload)
if ($code -ne 0) { throw "Notification activation returned HRESULT $code" }
[pscustomobject]@{OfferId=$offer.fields.offerId;Action=$Action;HResult=$code} | ConvertTo-Json -Compress
