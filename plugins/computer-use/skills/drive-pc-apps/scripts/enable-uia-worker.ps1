# enable-uia-worker.ps1  — run from an ELEVATED PowerShell (Run as administrator)
#
# Enables cua-driver's UIAccess worker so the driver can take the foreground and drive
# Win32 menus / custom-drawn panes (bring_to_front + dispatch:"foreground").
#
# What it changes (security-relevant, reversible — do only with the user's consent):
#   1. Creates a self-signed code-signing cert and trusts it machine-wide
#      (LocalMachine\Root + LocalMachine\TrustedPublisher).
#   2. Signs cua-driver-uia.exe (UIAccess PEs must be signed by a trusted publisher).
#   3. Sets HKLM ...\Policies\System\EnableSecureUIAPaths = 0 so the signed worker may
#      launch from its (non-secure) AppData location.
# After this, start the daemon with CUA_DRIVER_RS_SPAWN_UIA_WORKER=1 and reconnect the MCP.
# Undo notes at the bottom.

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this from an ELEVATED PowerShell (Run as administrator)."
}

# Auto-discover the worker exe(s) — install-dir bin copy + any versioned release copy.
$candidates = @(
    "$env:LOCALAPPDATA\Programs\Cua\cua-driver\bin\cua-driver-uia.exe"
) + (Get-ChildItem "$env:USERPROFILE\.cua-driver\packages\releases\*\cua-driver-uia.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName)
$workers = $candidates | Where-Object { Test-Path $_ } | Select-Object -Unique
if (-not $workers) { throw "cua-driver-uia.exe not found. Install cua-driver first (see cua-driver-windows-setup.md)." }

Write-Host "[1/4] Creating self-signed code-signing certificate..."
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Cua UIA Local Signing" `
        -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -KeySpec Signature `
        -NotAfter (Get-Date).AddYears(5)
Write-Host "      thumbprint $($cert.Thumbprint)"

Write-Host "[2/4] Trusting the cert (LocalMachine Root + TrustedPublisher)..."
$tmp = Join-Path $env:TEMP "cua_uia_signing.cer"
Export-Certificate -Cert $cert -FilePath $tmp | Out-Null
Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\Root           | Out-Null
Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
[IO.File]::Delete($tmp)

Write-Host "[3/4] Signing the UIAccess worker(s)..."
foreach ($w in $workers) {
    $r = Set-AuthenticodeSignature -FilePath $w -Certificate $cert -HashAlgorithm SHA256
    Write-Host ("      {0}  -> {1}" -f $w, $r.Status)
}

Write-Host "[4/4] Allowing signed UIAccess apps from non-secure paths..."
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name EnableSecureUIAPaths -Value 0 -PropertyType DWord -Force | Out-Null

Write-Host "`n[verify] Launching the worker to confirm UIAccess is granted..."
try {
    $p = Start-Process $workers[0] -PassThru; Start-Sleep -Milliseconds 1200
    if ($p.HasExited) { Write-Host "      worker exited (code $($p.ExitCode)) - can be normal for a handshake binary." }
    else { Write-Host "      worker RUNNING (pid $($p.Id)) - UIAccess launch succeeded."; try { $p.Kill() } catch {} }
} catch { Write-Host "      LAUNCH STILL FAILING: $($_.Exception.Message)" }

Write-Host "`nDONE. Next (NON-elevated, so the worker runs at matching integrity):"
Write-Host '  cua-driver stop'
Write-Host '  $env:CUA_DRIVER_RS_SPAWN_UIA_WORKER=1; cua-driver serve     # run/background'
Write-Host "  then reconnect the cua-computer-use MCP in Claude Code (/mcp -> reconnect)."

# ---- UNDO (elevated) ----
# Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableSecureUIAPaths
# Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher |
#   Where-Object Subject -eq 'CN=Cua UIA Local Signing' | Remove-Item
