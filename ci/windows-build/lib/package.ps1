# Assemble the runnable folder, then audit every file in it.

$script:CodeExtensions = @('.exe','.dll','.sys','.node','.pyd','.ps1','.psm1','.bat','.cmd','.vbs','.js','.mjs','.py','.msi','.scr','.com','.lnk','.ptx','.qml')
$script:DataExtensions = @('.json','.onnx','.tflite')

function Copy-Tree([string]$From, [string]$To) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    Copy-Item -Path (Join-Path $From '*') -Destination $To -Recurse -Force
}

function New-VeyraPackage($Pins, [string]$Root, [string]$Src, [hashtable]$Paths, [hashtable]$Built) {
    Write-Step 'Assemble the runnable folder'
    $dist = Join-Path $Root 'dist'
    $app = Join-Path $dist 'Veyra-2.2.0-metalito'
    if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $app | Out-Null

    # 1. Programs and libraries YOU compiled (FFmpeg/dav1d/zlib built from source by vcpkg).
    Copy-Item -LiteralPath $Built.Exe -Destination $app
    $ffmpegBin = Join-Path $Root 'vcpkg\installed\x64-windows\bin'
    Get-ChildItem -LiteralPath $ffmpegBin -Filter '*.dll' | Copy-Item -Destination $app
    Copy-Tree (Join-Path $Built.Build 'shaders') (Join-Path $app 'shaders')

    # 2. Interface and translations from YOUR fork's source (includes the PSN fix).
    Copy-Tree (Join-Path $Src 'qml\Veyra') (Join-Path $app 'qml\Veyra')
    Copy-Tree (Join-Path $Src 'i18n') (Join-Path $app 'i18n')
    Set-Content -LiteralPath (Join-Path $app 'qt.conf') -Encoding ascii -Value @(
        '[Paths]', 'Prefix=.', 'Plugins=.', 'QmlImports=qml', 'Translations=translations')

    # 3. Qt runtime from YOUR Qt install (Qt-signed), and the Microsoft C++ runtime.
    Invoke-Checked (Join-Path $Paths.Qt 'bin\windeployqt.exe') @('--release', '--no-translations', '--no-opengl-sw',
        '--qmldir', (Join-Path $Src 'qml\Veyra'), (Join-Path $app 'veyra_qml_ui.exe'))
    $crt = Get-ChildItem -LiteralPath (Join-Path $Paths.Vs 'VC\Redist\MSVC') -Directory |
        Where-Object Name -Match '^\d+\.' | Sort-Object Name -Descending | Select-Object -First 1
    foreach ($n in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
        Copy-Item -LiteralPath (Join-Path $crt.FullName "x64\Microsoft.VC143.CRT\$n") -Destination $app
    }

    # 4. Vendor runtimes from the official zip: signed NVIDIA/AMD/Intel DLLs + plain data only.
    Copy-OfficialRuntime $Pins $Root $app
    return $app
}

function Copy-OfficialRuntime($Pins, [string]$Root, [string]$App) {
    Write-Step 'Vendor runtime DLLs from the official 2.2.0 zip (signature-checked)'
    $zip = Join-Path $Root 'downloads\Veyra-2.2.0-NVIDIA-win64-portable.zip'
    if (-not (Test-Path -LiteralPath $zip)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zip) | Out-Null
        Invoke-WebRequest -Uri $Pins.OfficialZipUrl -OutFile $zip -UseBasicParsing
    }
    Assert-Sha256 $zip $Pins.OfficialZipSha256
    $tmp = Join-Path $Root 'tmp\official'
    if (-not (Test-Path -LiteralPath $tmp)) { Expand-Archive -LiteralPath $zip -DestinationPath $tmp }
    $ver = Join-Path $tmp 'Veyra-2.2.0-NVIDIA-win64-portable\versions\2.2.0'
    $files = @(Get-ChildItem -LiteralPath (Join-Path $ver 'runtime'), (Join-Path $ver 'runtime_local') -Recurse -File)
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($ver.Length + 1).Replace('\', '/')
        if ($Pins.ExcludedRuntimePaths | Where-Object { $rel.StartsWith($_ + '/') }) { Write-Info "skip (excluded)  $rel"; continue }
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -eq '.dll') {
            $signer = Get-ValidSigner $f.FullName
            if ($Pins.RuntimeSigners -notcontains $signer) { Write-Info "skip (not vendor-signed)  $rel"; continue }
            Write-Info "take ($signer)  $rel"
        } elseif ($script:DataExtensions -contains $ext) {
            Write-Info "take (data)  $rel"
        } else { Write-Info "skip ($ext)  $rel"; continue }
        $dest = Join-Path $App $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest
    }
    Copy-Item -LiteralPath (Join-Path $ver 'vfg-runtime-manifest.json') -Destination $App
    foreach ($d in @('media', 'assets', 'licenses', 'docs')) {
        Get-ChildItem -LiteralPath (Join-Path $ver $d) -Recurse -File | Where-Object {
            $script:CodeExtensions -notcontains $_.Extension.ToLowerInvariant() } | ForEach-Object {
            $dest = Join-Path $App $_.FullName.Substring($ver.Length + 1)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $dest
        }
    }
}
