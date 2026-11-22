# Windows build of this fork

These scripts build this fork (Veyra 2.2.0 plus the [PSN Account ID fix](../../docs/PSN_ACCOUNT_ID.md)) from source, either on GitHub Actions ([`windows-build.yml`](../../.github/workflows/windows-build.yml)) or on your own Windows 11 PC.

## What the build does

- **Pins every source** in [`pins.psd1`](pins.psd1) to an exact commit or SHA-256: this fork's commit (its parent must be upstream v2.2.0), Microsoft vcpkg, NVIDIA DLSS SDK headers, nv-codec-headers, chiaki-ng with Veyra's patches 0001–0004, and Qt 6.8.3 from the official Qt servers.
- **Python tools are hash-locked.** Every file in [`requirements.lock.txt`](requirements.lock.txt) is installed with `--require-hashes`, wheels only.
- **Builds FFmpeg** from source with Veyra's PS5 slices patch.
- **NVIDIA/AMD/Intel runtime DLLs** (DLSS, VSR, frame generation…) come from the official v2.2.0 release zip after its SHA-256 check. Only DLLs with a **valid signature from NVIDIA, AMD or Intel** are copied. The unsigned community NR DLL and the Magewell low-latency files are left out.
- **Audit** (`dist\audit-report.txt`). The build fails if:
  - any program file is neither built here nor validly signed by an allowed publisher;
  - any interface file differs from the source;
  - any script file is in the package;
  - the program still mentions psntools.

## Download a GitHub build

1. **Actions** tab → **Windows build (fork)** → the latest green run → **Artifacts** → `Veyra-2.2.0-metalito-win64`.
2. Check that it was built here, from this repository (needs the [GitHub CLI](https://cli.github.com/)):
   ```
   gh attestation verify Veyra-2.2.0-metalito-win64.zip -R metalito/Veyra-NRVideo
   ```
3. Unzip it and run `veyra_qml_ui.exe` from a **standard (non-admin)** Windows account.

## Build it yourself

You need Visual Studio 2022 Build Tools (C++ workload and Windows 11 SDK), Git, CMake, Ninja and Python 3.11. Then, as a normal user:

```
powershell -ExecutionPolicy Bypass -File .\ci\windows-build\2-build-veyra.ps1
```

The first run takes 1–2 hours. The result is in `C:\VeyraBuild\dist`.

Use `-CI` only on GitHub's throwaway machines. It skips the "not administrator" check.
