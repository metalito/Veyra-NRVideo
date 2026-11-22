<#
.SYNOPSIS
    Build your Veyra fork (metalito/Veyra-NRVideo, PSN fix) from source on Windows 11.
.DESCRIPTION
    Run as a NORMAL user (not administrator), after 1-install-prerequisites.ps1.
    Safe to re-run: finished steps are reused, every pin is re-checked each time.
    Result: <Root>\dist\Veyra-2.2.0-metalito\veyra_qml_ui.exe plus audit-report.txt.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\2-build-veyra.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\2-build-veyra.ps1 -Root D:\VeyraBuild
.PARAMETER CI
    Only for the GitHub Actions build: the throwaway GitHub machine runs as administrator,
    so the not-admin check is skipped there. Never use it on your own PC.
#>
[CmdletBinding()]
param([string]$Root = 'C:\VeyraBuild', [switch]$CI)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
foreach ($lib in @('common', 'deps', 'build', 'package', 'audit')) { . (Join-Path $Here "lib\$lib.ps1") }
$Pins = Import-PowerShellDataFile -LiteralPath (Join-Path $Here 'pins.psd1')

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'logs') | Out-Null
$script:LogFile = Join-Path $Root ("logs\build-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
$started = Get-Date

try {
    Write-Step "Preflight (log: $script:LogFile)"
    if ($CI) { Write-Info 'CI mode: GitHub-hosted runner, admin check skipped' } else { Assert-NotAdmin }
    $vs = Enter-VsDevEnvironment
    foreach ($tool in @('git', 'cmake', 'ninja')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found. Run 1-install-prerequisites.ps1 (as admin) first, then open a NEW PowerShell window." }
    }

    Write-Step 'Your fork at the pinned commit'
    $src = Join-Path $Root 'src'
    Get-PinnedGit $Pins.ForkRepo $src $Pins.ForkCommit
    $parent = ((Invoke-Native 'git' @('-C', $src, 'rev-parse', 'HEAD^')) -join '').Trim()
    if ($parent -ne $Pins.UpstreamParentCommit) { throw "Fork commit's parent is $parent, expected upstream v2.2.0 $($Pins.UpstreamParentCommit)" }
    Write-Info 'Only change on top of upstream v2.2.0 (should be the PSN fix):'
    Invoke-Native 'git' @('-C', $src, 'diff', '--stat', $Pins.UpstreamParentCommit, 'HEAD') | ForEach-Object { Write-Info "  $_" }

    $py      = Install-PythonTools $Root $Here
    $qt      = Install-Qt $Pins $Root $py
    $dlss    = Get-DlssSdk $Pins $Root
    $nvcodec = Get-NvCodecHeaders $Pins $Root
    $chiaki  = Get-ChiakiStage $Pins $Root $src
    Install-VcpkgDeps $Pins $Root $src

    $paths = @{ Qt = $qt; Python = $py; Dlss = $dlss; NvCodec = $nvcodec; Vs = $vs
                ChiakiStage = $chiaki.Stage; ChiakiClean = $chiaki.Clean }
    $built = Invoke-VeyraBuild $Pins $Root $src $paths
    $app   = New-VeyraPackage $Pins $Root $src $paths $built
    Invoke-PackageAudit $Pins $app $src $paths $built $Root

    Write-Step ("DONE in {0:N0} min" -f ((Get-Date) - $started).TotalMinutes)
    Write-Info "Run:    $app\veyra_qml_ui.exe"
    Write-Info "Audit:  $(Join-Path (Split-Path -Parent $app) 'audit-report.txt')"
} catch {
    Write-Host "`nBUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Add-Content -LiteralPath $script:LogFile -Value "BUILD FAILED: $($_.Exception.Message)"
    Write-Host "Full log: $script:LogFile"
    exit 1
}
