# Dependency stage. Every source is pinned in pins.psd1; nothing comes from Discord,
# mirrors or the Veyra author's binaries.

function Install-VcpkgDeps($Pins, [string]$Root, [string]$Src) {
    Write-Step 'vcpkg (Microsoft) at the Veyra baseline'
    $vcpkg = Join-Path $Root 'vcpkg'
    Get-PinnedGit $Pins.VcpkgRepo $vcpkg $Pins.VcpkgCommit
    $env:VCPKG_DISABLE_METRICS = '1'
    if (-not (Test-Path -LiteralPath (Join-Path $vcpkg 'vcpkg.exe'))) {
        Invoke-Checked (Join-Path $vcpkg 'bootstrap-vcpkg.bat') @('-disableMetrics')
    }

    Write-Step 'FFmpeg overlay port = vcpkg ffmpeg 9.0.1 + Veyra PS5 slices patch'
    $overlay = Join-Path $Root 'overlay-ports'
    if (Test-Path -LiteralPath $overlay) { Remove-Item -LiteralPath $overlay -Recurse -Force }
    $port = Join-Path $overlay 'ffmpeg'
    Copy-Item -LiteralPath (Join-Path $vcpkg 'ports\ffmpeg') -Destination $port -Recurse
    $patch = Join-Path $Src $Pins.FfmpegSlicesPatch
    Assert-Sha256 $patch $Pins.FfmpegSlicesPatchSha256
    Copy-Item -LiteralPath $patch -Destination (Join-Path $port 'ps5-h264-slices.patch')
    $portfile = Join-Path $port 'portfile.cmake'
    $text = [IO.File]::ReadAllText($portfile)
    $re = [regex]'(?m)^(\s*)PATCHES\s*$'
    if (-not $re.IsMatch($text)) { throw 'ffmpeg portfile layout changed: PATCHES list not found' }
    $text = $re.Replace($text, "`$1PATCHES`n`$1    ps5-h264-slices.patch", 1)
    [IO.File]::WriteAllText($portfile, $text)
    Write-Info 'ps5-h264-slices.patch added to the ffmpeg port'

    Write-Step 'vcpkg install (first run builds FFmpeg from source: 20-60 min)'
    Push-Location $Root   # classic mode: never run inside the Veyra tree (it has a vcpkg.json)
    try {
        Invoke-Checked (Join-Path $vcpkg 'vcpkg.exe') @('install', "--overlay-ports=$overlay",
            '--triplet', 'x64-windows', '--disable-metrics',
            'ffmpeg[core,avcodec,avformat,avfilter,swresample,swscale,dav1d,zlib]')
        Invoke-Checked (Join-Path $vcpkg 'vcpkg.exe') @('install', '--triplet', 'x64-windows-static-md',
            '--disable-metrics', 'openssl', 'opus', 'json-c', 'libevent', 'miniupnpc', 'curl',
            'protobuf', 'sdl3', 'zlib')
    } finally { Pop-Location }
    $h264 = Get-ChildItem -LiteralPath (Join-Path $vcpkg 'buildtrees\ffmpeg\src') -Recurse -Filter 'h264dec.h' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($h264 -and -not (Select-String -LiteralPath $h264.FullName -Pattern 'define MAX_SLICES 256' -Quiet)) {
        throw 'FFmpeg was built without the PS5 slices patch'
    }
}

function Install-PythonTools([string]$Root, [string]$Here) {
    Write-Step 'Python tools (aqtinstall, protobuf) - every file hash-locked'
    $venv = Join-Path $Root 'venv'
    if (-not (Test-Path -LiteralPath (Join-Path $venv 'Scripts\python.exe'))) {
        # VEYRA_PYTHON: full path to a Python 3.11 python.exe (set by the GitHub workflow).
        if ($env:VEYRA_PYTHON) { Invoke-Checked $env:VEYRA_PYTHON @('-m', 'venv', $venv) }
        elseif (Get-Command 'py' -ErrorAction SilentlyContinue) { Invoke-Checked 'py' @('-3.11', '-m', 'venv', $venv) }
        else { throw 'py (Python launcher) not found. Run 1-install-prerequisites.ps1 (as admin) first, then open a NEW PowerShell window.' }
    }
    $py = Join-Path $venv 'Scripts\python.exe'
    Invoke-Checked $py @('-m', 'pip', 'install', '--disable-pip-version-check', '--require-hashes',
        '--no-deps', '--only-binary', ':all:', '-r', (Join-Path $Here 'requirements.lock.txt'))
    return $py
}

function Install-Qt($Pins, [string]$Root, [string]$Py) {
    Write-Step "Qt $($Pins.QtVersion) from the official Qt servers"
    $qtDir = Join-Path $Root "qt\$($Pins.QtVersion)\msvc2022_64"
    if (-not (Test-Path -LiteralPath (Join-Path $qtDir 'bin\windeployqt.exe'))) {
        Invoke-Checked $Py @('-m', 'aqt', 'install-qt', 'windows', 'desktop', $Pins.QtVersion,
            $Pins.QtArch, '-O', (Join-Path $Root 'qt'))
    }
    Write-Info "Qt at $qtDir"
    return $qtDir
}

function Get-DlssSdk($Pins, [string]$Root) {
    Write-Step "NVIDIA DLSS SDK $($Pins.DlssTag) (headers + static NGX lib only)"
    $dir = Join-Path $Root 'deps\DLSS'
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
        Invoke-Checked 'git' @('clone', '--filter=blob:none', '--no-checkout', '--depth', '1',
            '--branch', $Pins.DlssTag, $Pins.DlssRepo, $dir)
        Invoke-Checked 'git' @('-C', $dir, 'sparse-checkout', 'set', '--no-cone', '/include/',
            '/lib/Windows_x86_64/x64/nvsdk_ngx_s.lib', '/lib/Windows_x86_64/x64/nvsdk_ngx_s_dbg.lib',
            '/LICENSE.txt', '/license.txt')
        Invoke-Checked 'git' @('-C', $dir, 'checkout', '--quiet')
    }
    Assert-GitAt $dir $Pins.DlssCommit
    return $dir
}

function Get-NvCodecHeaders($Pins, [string]$Root) {
    Write-Step "nv-codec-headers $($Pins.NvCodecTag) (FFmpeg project)"
    $dir = Join-Path $Root 'deps\nv-codec-headers'
    Get-PinnedGit $Pins.NvCodecRepo $dir $Pins.NvCodecCommit
    return $dir
}

function Get-ChiakiStage($Pins, [string]$Root, [string]$Src) {
    Write-Step 'chiaki-ng (official) + Veyra patches 0001-0004'
    $clean = Join-Path $Root 'deps\chiaki-ng'
    Get-PinnedGit $Pins.ChiakiRepo $clean $Pins.ChiakiCommit
    # Veyra's verifier compares the patched stage against this clean reference, submodules included.
    Invoke-Checked 'git' @('-C', $clean, 'submodule', 'update', '--init', '--recursive')
    $stage = Join-Path $Root 'deps\chiaki-stage'
    if (-not (Test-Path -LiteralPath (Join-Path $stage '.git'))) {
        Invoke-Checked 'git' @('-C', $clean, 'worktree', 'add', '--detach', $stage, $Pins.ChiakiCommit)
    }
    Invoke-Checked 'git' @('-C', $stage, 'submodule', 'update', '--init', '--recursive')
    Write-Info 'Submodules (pinned by the chiaki-ng commit itself):'
    Invoke-Native 'git' @('-C', $stage, 'submodule', 'status', '--recursive') | ForEach-Object { Write-Info "  $_" }
    foreach ($rel in $Pins.ChiakiPatches) {
        $patch = Join-Path $Src $rel
        [void](Invoke-Native 'git' @('-C', $stage, 'apply', '--reverse', '--check', $patch))
        if ($LASTEXITCODE -eq 0) { Write-Info "already applied  $(Split-Path -Leaf $patch)"; continue }
        Invoke-Checked 'git' @('-C', $stage, 'apply', '--check', $patch)
        Invoke-Checked 'git' @('-C', $stage, 'apply', $patch)
        Write-Info "applied  $(Split-Path -Leaf $patch)"
    }
    return @{ Stage = $stage; Clean = $clean }
}
