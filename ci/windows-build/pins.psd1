# Every external input of the build, pinned. Review this file before running anything.
# A git source is accepted only if its checked-out commit equals the SHA below.
# A downloaded file is accepted only if its SHA-256 matches.
@{
    # Your fork: upstream v2.2.0 (fe8df532) + the PSN Account ID fix (93811492), nothing else.
    ForkRepo             = 'https://github.com/metalito/Veyra-NRVideo.git'
    ForkCommit           = '938114928d3964dc2245eef1520226166cb04aca'
    UpstreamParentCommit = 'fe8df5328a62849eb2d79053564b9574ab68aecd'

    # Microsoft vcpkg at the exact baseline in Veyra's vcpkg.json (FFmpeg 9.0.1#1, SDL3 3.4.14).
    VcpkgRepo   = 'https://github.com/microsoft/vcpkg.git'
    VcpkgCommit = '30ef65cad98f08e7197c9a1656fbd871bcb72f2d'

    # One-line FFmpeg patch from Veyra (MAX_SLICES 32 -> 256, needed for PS5 H.264).
    FfmpegSlicesPatch       = 'scripts/ffmpeg/ps5-h264-slices.patch'
    FfmpegSlicesPatchSha256 = 'E7D138926873FAF479EBDB17B59CECFD654086F5062220BA45AB08CCEE9FAE26'

    # NVIDIA's public DLSS SDK (headers + static NGX lib) - official NVIDIA GitHub.
    DlssRepo   = 'https://github.com/NVIDIA/DLSS.git'
    DlssTag    = 'v310.7.0'
    DlssCommit = 'a291cc7d2cc642a51566f3dfd5376f635cd1b284'

    # NVIDIA video-codec headers - official FFmpeg project.
    NvCodecRepo   = 'https://github.com/FFmpeg/nv-codec-headers.git'
    NvCodecTag    = 'n13.0.19.0'
    NvCodecCommit = 'e844e5b26f46bb77479f063029595293aa8f812d'

    # chiaki-ng (PS5 Remote Play) - official repo, commit from Veyra's dependency-lock.json.
    # Veyra's 4 patches (0003/0004 are backports of real upstream commits) are applied on top.
    ChiakiRepo    = 'https://github.com/chiaki-ng/chiaki-ng.git'
    ChiakiCommit  = '0e16950165f06e5c3291537c2eeba6e852be7120'
    ChiakiPatches = @(
        'scripts/remoteplay/patches/0001-chiaki-msvc-vla-compat.patch',
        'scripts/remoteplay/patches/0002-chiaki-video-metadata.patch',
        'scripts/remoteplay/patches/0003-chiaki-feedback-history.patch',
        'scripts/remoteplay/patches/0004-chiaki-pad-proc-no.patch'
    )

    # Qt from the official Qt servers via aqtinstall (hash-locked in requirements.lock.txt).
    QtVersion = '6.8.3'
    QtArch    = 'win64_msvc2022_64'

    # Official Veyra 2.2.0 package: used ONLY as a source of vendor-signed runtime DLLs
    # (NVIDIA / AMD / Intel) and data files. Every Veyra program, FFmpeg DLL and QML file
    # in your build comes from source you compiled, never from this zip.
    OfficialZipUrl    = 'https://github.com/Likely7/Veyra-NRVideo/releases/download/v2.2.0/Veyra-2.2.0-NVIDIA-win64-portable.zip'
    OfficialZipSha256 = 'FD1235483A6E36B2520966EC161104478CD93186E97AF3B0D78D2DFA7B129932'

    # Vendor DLLs from the zip must carry a VALID Authenticode signature from one of these.
    RuntimeSigners = @('NVIDIA Corporation', 'Advanced Micro Devices', 'Intel Corporation')

    # Signers accepted for any binary in the final folder that you did not build yourself.
    AllowedSigners = @('NVIDIA Corporation', 'Advanced Micro Devices', 'Intel Corporation',
                       'The Qt Company Oy', 'Microsoft Corporation',
                       'Microsoft Windows Software Compatibility Publisher')

    # Never copied from the official zip (community / unsigned / not needed for PS5).
    ExcludedRuntimePaths = @('runtime/experimental/nr-ampere', 'runtime/experimental/dlssg-kernels',
                             'runtime/magewell')
}
