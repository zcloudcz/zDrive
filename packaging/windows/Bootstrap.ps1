$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object Windows.Forms.Form
$form.Text = 'zDrive Setup'
$form.ClientSize = New-Object Drawing.Size(460, 145)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ControlBox = $false
$label = New-Object Windows.Forms.Label
$label.SetBounds(20, 20, 420, 45)
$label.Text = 'Preparing zDrive installation...'
$progress = New-Object Windows.Forms.ProgressBar
$progress.SetBounds(20, 75, 420, 20)
$progress.Style = 'Marquee'
$close = New-Object Windows.Forms.Button
$close.Text = 'Close'
$close.SetBounds(350, 108, 90, 27)
$close.Enabled = $false
$close.Add_Click({ $form.Close() })
$launch = New-Object Windows.Forms.Button
$launch.Text = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -in @('cs', 'sk')) { 'Spustit zDrive' } else { 'Launch zDrive' }
$launch.SetBounds(205, 108, 135, 27)
$launch.Visible = $false
$launch.Add_Click({
    $launch.Enabled = $false
    try {
        Start-Process -FilePath $launch.Tag -WorkingDirectory (Split-Path -Parent $launch.Tag) -WindowStyle Normal -ErrorAction Stop
        $form.Close()
    }
    catch {
        $label.Text = "zDrive is installed, but could not start: $($_.Exception.GetBaseException().Message). Open it from the Start menu."
        $launch.Enabled = $true
    }
})
$form.Controls.AddRange(@($label, $progress, $launch, $close))
$form.Show()
[Windows.Forms.Application]::DoEvents()
$work = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Setup-' + [guid]::NewGuid().ToString('N'))
$exitCode = 0
try {
    # Use Windows PowerShell's modules even when launched from PowerShell 7.
    Import-Module "$PSHOME/Modules/Microsoft.PowerShell.Utility", "$PSHOME/Modules/Microsoft.PowerShell.Archive" -Force
    $release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
    $uri = [Uri]$release.url
    if ($uri.Scheme -ne 'https' -or $release.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid installer configuration.' }
    New-Item -ItemType Directory -Path $work | Out-Null
    $archive = Join-Path $work 'payload.zip'
    $label.Text = 'Downloading zDrive...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $download = New-Object Net.WebClient
    try {
        $task = $download.DownloadFileTaskAsync($uri, $archive)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not $task.IsCompleted) {
            [Windows.Forms.Application]::DoEvents()
            if ($timer.Elapsed.TotalMinutes -gt 10) { $download.CancelAsync(); throw 'Download timed out. Please retry.' }
            Start-Sleep -Milliseconds 50
        }
        $task.GetAwaiter().GetResult()
    }
    finally { $download.Dispose() }
    $label.Text = 'Verifying download...'
    [Windows.Forms.Application]::DoEvents()
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $release.sha256) { throw 'Download integrity check failed.' }
    $label.Text = 'Extracting application files...'
    [Windows.Forms.Application]::DoEvents()
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $work 'payload')
    $label.Text = 'Installing zDrive and creating shortcuts...'
    [Windows.Forms.Application]::DoEvents()
    & (Join-Path $work 'payload/Install.ps1')
    $installedVersion = (Get-Content -LiteralPath (Join-Path $work 'payload/version.txt') -Raw).Trim()
    if ($installedVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') { throw 'Invalid installed version.' }
    $launch.Tag = Join-Path $env:LOCALAPPDATA "Programs/zDrive/releases/$installedVersion/zdrive_app.exe"
    $launch.Visible = $true
    $label.Text = 'zDrive is installed. Open zDrive from the Start menu.'
}
catch {
    $exitCode = 1
    $label.Text = "Installation failed: $($_.Exception.GetBaseException().Message)"
}
finally {
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($work).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    $progress.Style = 'Continuous'
    $progress.Value = if ($exitCode -eq 0) { 100 } else { 0 }
    $close.Enabled = $true
    $form.ControlBox = $true
    while ($form.Visible) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
    $form.Dispose()
}
exit $exitCode
