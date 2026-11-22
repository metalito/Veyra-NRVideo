# Configure and compile Veyra with MSVC + Ninja.

function Invoke-VeyraBuild($Pins, [string]$Root, [string]$Src, [hashtable]$Paths) {
    Write-Step 'Configure Veyra (CMake + Ninja, Release)'
    $build = Join-Path $Root 'build'
    $vcpkg = Join-Path $Root 'vcpkg'
    $protoc = Get-ChildItem -LiteralPath (Join-Path $vcpkg 'installed') -Recurse -Filter 'protoc.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $protoc) { throw 'protoc.exe not found in the vcpkg tree (protobuf install failed?)' }
    $cmakeArgs = @(
        '-S', $Src, '-B', $build, '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release',
        "-DCMAKE_TOOLCHAIN_FILE=$vcpkg\scripts\buildsystems\vcpkg.cmake",
        '-DVCPKG_TARGET_TRIPLET=x64-windows-static-md',
        '-DVCPKG_MANIFEST_MODE=OFF',
        "-DCMAKE_PREFIX_PATH=$($Paths.Qt)",
        "-DPython3_EXECUTABLE=$($Paths.Python)",
        "-DPython_EXECUTABLE=$($Paths.Python)",
        "-DPYTHON_EXECUTABLE=$($Paths.Python)",
        "-DPROTOC=$($protoc.FullName)",
        '-DVEYRA_BUILD_QML_UI=ON',
        '-DVEYRA_ENABLE_REMOTEPLAY=ON',
        "-DVEYRA_RP_CHIAKI_SOURCE_DIR=$($Paths.ChiakiStage)",
        "-DVEYRA_RP_CHIAKI_VERIFY_DIR=$($Paths.ChiakiClean)",
        # NVIDIA VSR / TrueHDR / DLSS-G live in veyra_ngx, compiled only with this switch.
        '-DVEYRA_ENABLE_EXPERIMENTAL_DLSSNR=ON',
        "-DVEYRA_DLSS_SDK_ROOT=$($Paths.Dlss)",
        "-DVEYRA_FFMPEG_ROOT=$vcpkg\installed\x64-windows",
        "-DVEYRA_NVENC_HEADERS_ROOT=$($Paths.NvCodec)",
        '-DVEYRA_ENABLE_LIBDOVI=OFF',      # Dolby Vision RPU parsing: not needed for PS5
        '-DVEYRA_ENABLE_MOONLIGHT=OFF',
        '-DVEYRA_ENABLE_XBOX=OFF',
        '-DVEYRA_ENABLE_D3D12_DEBUG=OFF',
        '-DVEYRA_UPDATE_PUBLIC_KEY=',      # no update trust root: nothing can auto-install over your build
        '-DVEYRA_UPDATE_TEST_PORT=',
        '-DVEYRA_DISPLAY_VERSION=2.2.0-metalito',
        '-DBUILD_TESTING=OFF'
    )
    Invoke-Checked 'cmake' $cmakeArgs

    Write-Step 'Compile (first run: 10-30 min)'
    $jobs = [Math]::Max(2, [Environment]::ProcessorCount - 2)
    Invoke-Checked 'cmake' @('--build', $build, '--target', 'veyra_qml_ui', '--parallel', "$jobs")
    $shaders = @(Get-ChildItem -LiteralPath (Join-Path $build 'shaders') -Recurse -File -ErrorAction SilentlyContinue)
    if ($shaders.Count -eq 0) {
        Write-Info 'Shaders are not a dependency of veyra_qml_ui here; building all default targets'
        Invoke-Checked 'cmake' @('--build', $build, '--parallel', "$jobs")
    }
    $exe = Get-ChildItem -LiteralPath $build -Recurse -Filter 'veyra_qml_ui.exe' |
        Where-Object { $_.FullName -notmatch '\\CMakeFiles\\' } | Select-Object -First 1
    if (-not $exe) { throw 'veyra_qml_ui.exe was not produced' }
    Write-Info "built $($exe.FullName)"
    return @{ Build = $build; Exe = $exe.FullName }
}
