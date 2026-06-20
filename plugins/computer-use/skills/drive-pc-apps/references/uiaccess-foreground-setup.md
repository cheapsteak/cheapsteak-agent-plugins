# UIAccess foreground worker setup (Windows)

Background `PostMessage`/UIA-invoke drives standard controls without focus. But **Win32 menus and
custom-drawn panes only react to real foreground input** (`bring_to_front` + `dispatch:"foreground"`).
A normal-integrity process can't take the foreground (Windows foreground-lock), so cua-driver ships
a **UIAccess worker** (`cua-driver-uia.exe`) it routes foreground ops through. UIAccess PEs must be
**signed by a trusted publisher**; the shipped worker is unsigned, so it must be signed once.

This is a security-relevant, admin-required, one-time setup. It trusts a self-signed cert
machine-wide and relaxes one UAC policy. Do it only with the user's consent.

## One-time setup (elevated PowerShell)

Run the bundled script from an **elevated** PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/enable-uia-worker.ps1
```

It (1) creates a self-signed code-signing cert and trusts it machine-wide (LocalMachine Root +
TrustedPublisher), (2) auto-discovers and signs `cua-driver-uia.exe` (the bin copy + any versioned
release copy), (3) sets `HKLM ...\Policies\System\EnableSecureUIAPaths = 0`, then launches the worker
to verify UIAccess is granted. Undo notes are in the script footer. (If you can't run scripts, the
equivalent steps are: New-SelfSignedCertificate -Type CodeSigningCert → Import to LocalMachine Root +
TrustedPublisher → Set-AuthenticodeSignature on the worker exe(s) → EnableSecureUIAPaths=0.)

## Start the daemon so it spawns the worker

The daemon spawns the worker only when `CUA_DRIVER_RS_SPAWN_UIA_WORKER` is set (v0.5.7+):

```bash
cua-driver stop
CUA_DRIVER_RS_SPAWN_UIA_WORKER=1 cua-driver serve   # run/background
```

Then reconnect the `cua-computer-use` MCP in Claude Code (`/mcp` → reconnect) so the proxy attaches
to the new daemon. Verify: `bring_to_front(pid)` returns `landed_on_target: true`.

## Pitfalls
- **Don't launch the worker elevated/standalone.** An admin-launched worker squats
  `\\.\pipe\cua-driver-uia` at high integrity and the normal-integrity proxy gets `Access denied`
  → MCP won't connect. Let the **daemon** spawn it (so it runs at matching integrity). If you hit
  this, kill the orphan (elevated `taskkill /F /IM cua-driver-uia.exe`) and restart the daemon.
- **The auto-updater may stall** migrating "legacy layout"; if so, install the release zip's
  `cua-driver.exe` + `cua-driver-uia.exe` into the `bin` dir manually, then re-sign the worker.
- Upgrading replaces the worker binary → **re-sign** it (the cert + policy persist).

## Undo (elevated)
```powershell
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableSecureUIAPaths
Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher |
  Where-Object Subject -eq 'CN=Cua UIA Local Signing' | Remove-Item
```
