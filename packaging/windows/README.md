# Windows installer

Like NetworkPrinter, zDrive uses the Windows IExpress packager for a small online
installer. Setup embeds the immutable payload URL and its SHA-256 digest, downloads
the ZIP over HTTPS, and verifies the digest **before extraction or execution**.
No downloaded release manifest can change the pinned digest. Publish the generated
ZIP at exactly that URL and never replace a released version's payload.

Build on Windows with PowerShell 5.1+ and IExpress (included in Windows). First
build the production-configured Flutter x64 release. Include the x64 Visual C++
redistributable DLLs from your licensed Visual Studio installation, either in the
release folder or via `RuntimeDirectory`. All other Flutter release files and
plugin DLLs are copied recursively.

```powershell
./scripts/Package-Windows.ps1 `
  -ReleaseDirectory ./src/client/zdrive_app/build/windows/x64/runner/Release `
  -RuntimeDirectory 'C:/path/to/VC/Redist/MSVC/version/x64/Microsoft.VC145.CRT' `
  -Version 0.2.0 `
  -PayloadUrl 'https://drive.zcloud.cz/downloads/zDrive-0.2.0-windows-x64.zip'
```

Outputs go to ignored `build/windows-installer`: payload ZIP, setup EXE (limited
to 5 MB), release metadata and SHA-256 sidecars. No upload occurs. Hosting must be
public; a private GitHub release asset is unsuitable. Setup is unsigned unless
your release process signs the generated EXE. IExpress provides its standard icon;
the installed app and shortcuts use the icon embedded in `zdrive_app.exe`.

Installation requires no administrator permissions. Application binaries go under
`%LOCALAPPDATA%/Programs/zDrive/releases/<version>`. Start-menu and desktop shortcuts
point to that version. Re-running setup upgrades those shortcuts and the stable
`HKCU/Software/Microsoft/Windows/CurrentVersion/Uninstall/zDrive` entry. Close the
app before updating or uninstalling. Older binaries remain until uninstall;
uninstall removes only the release directories, shortcuts and uninstall entry.
Application settings, credentials and synchronized files are preserved.

The build procedure is repeatable; ZIP timestamps and IExpress metadata mean the
bytes are not guaranteed reproducible. Always distribute the ZIP and bootstrapper
from the same invocation; the bootstrapper rejects any differently hashed ZIP.
Test install, upgrade and uninstall in a disposable Windows account or VM; do not
run these smoke tests against a real user's profile.


Setup displays a Windows dialog with download, verification, extraction and
installation stages, an animated progress bar, and a Close button after success
or failure. It does not wait for input in a hidden console. Downloads time out
after ten minutes. Run the isolated file-operation smoke test with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/packaging/Windows-Installer.Smoke.ps1
```

The test exercises installation, upgrade, running-app rejection, incomplete
payload rejection and uninstall using real temporary files. Registry entries
and COM shortcuts are mocked; the real profile remains untouched.
