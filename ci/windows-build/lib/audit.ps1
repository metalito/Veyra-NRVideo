# Final audit. The build FAILS if anything in the output folder is not accounted for.

function Invoke-PackageAudit($Pins, [string]$App, [string]$Src, [hashtable]$Paths, [hashtable]$Built, [string]$Root) {
    Write-Step 'Audit: every program, DLL and script in the folder'
    $ours = @{}
    $ffmpegBin = Join-Path $Root 'vcpkg\installed\x64-windows\bin'
    foreach ($f in @($Built.Exe) + @(Get-ChildItem -LiteralPath $ffmpegBin -Filter '*.dll' | ForEach-Object FullName)) {
        $ours[(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash] = $f
    }
    $knownText = @{}
    foreach ($dir in @((Join-Path $Src 'qml\Veyra'), (Join-Path $Paths.Qt 'qml'))) {
        Get-ChildItem -LiteralPath $dir -Recurse -File -Include '*.qml', '*.js', '*.mjs' |
            ForEach-Object { $knownText[(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash] = $true }
    }
    $report = New-Object System.Collections.Generic.List[string]
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($f in Get-ChildItem -LiteralPath $App -Recurse -File) {
        $rel = $f.FullName.Substring($App.Length + 1)
        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        $ext = $f.Extension.ToLowerInvariant()
        if (Test-IsPortableExecutable $f.FullName) {
            if ($ours.ContainsKey($hash)) { $report.Add("BUILT-BY-YOU  $hash  $rel"); continue }
            $signer = Get-ValidSigner $f.FullName
            if ($signer -and $Pins.AllowedSigners -contains $signer) { $report.Add("SIGNED($signer)  $hash  $rel"); continue }
            $problems.Add("UNACCOUNTED BINARY  $rel  (signer: $signer)")
        } elseif (@('.qml', '.js', '.mjs') -contains $ext) {
            if ($knownText.ContainsKey($hash)) { $report.Add("SOURCE  $hash  $rel") }
            else { $problems.Add("QML/JS NOT FROM YOUR SOURCE OR QT  $rel") }
        } elseif (@('.ps1', '.psm1', '.bat', '.cmd', '.vbs', '.py', '.msi', '.scr', '.com', '.lnk', '.ptx', '.sys') -contains $ext) {
            $problems.Add("UNEXPECTED SCRIPT/CODE FILE  $rel")
        } else { $report.Add("DATA  $hash  $rel") }
    }

    Write-Step 'Audit: the PSN fix is in, psntools is out'
    $settings = Join-Path $App 'qml\Veyra\SettingsPage.qml'
    if (Select-String -LiteralPath $settings -Pattern 'PSNTools' -SimpleMatch -Quiet) { $problems.Add('SettingsPage.qml still mentions PSNTools') }
    $bytes = [IO.File]::ReadAllBytes((Join-Path $App 'veyra_qml_ui.exe'))
    $ascii = [Text.Encoding]::ASCII.GetString($bytes); $wide = [Text.Encoding]::Unicode.GetString($bytes)
    if ($ascii -match 'psntools' -or $wide -match 'psntools') { $problems.Add('veyra_qml_ui.exe still contains psntools') }
    if (-not ($ascii -match 'PSN_ACCOUNT_ID\.md' -or $wide -match 'PSN_ACCOUNT_ID\.md')) { $problems.Add('veyra_qml_ui.exe lacks the Account ID guide link') }

    $reportFile = Join-Path (Split-Path -Parent $App) 'audit-report.txt'
    Set-Content -LiteralPath $reportFile -Encoding ascii -Value ($report + @('', 'PROBLEMS:') + $problems)
    if ($problems.Count) {
        $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        throw "Audit FAILED: $($problems.Count) problem(s). See $reportFile. Do NOT run this build."
    }
    Write-Info "Audit passed: $($report.Count) files accounted for. Report: $reportFile"
}
