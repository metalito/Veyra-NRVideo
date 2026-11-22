# Shared helpers: logging, checked process calls, pinned git checkouts, signatures.
# Windows PowerShell 5.1 compatible. ASCII only.

function Write-Step([string]$Text) {
    $line = "`n=== $Text ==="
    Write-Host $line -ForegroundColor Cyan
    Add-Content -LiteralPath $script:LogFile -Value $line
}

function Write-Info([string]$Text) {
    Write-Host "  $Text"
    Add-Content -LiteralPath $script:LogFile -Value "  $Text"
}

# Native programs (git, cmake, vcpkg...) write progress to stderr. Windows PowerShell 5.1
# turns stderr into terminating errors when $ErrorActionPreference is Stop, so native calls
# run with a local 'Continue' and are judged by their exit code only.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $out = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
    return $out
}

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    Add-Content -LiteralPath $script:LogFile -Value "  > $Exe $($Arguments -join ' ')"
    & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $script:LogFile -Append | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE (see $script:LogFile)" }
}

function Assert-NotAdmin {
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if ($id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run the build as a normal (non-administrator) user. Only 1-install-prerequisites.ps1 needs admin.'
    }
}

function Assert-Sha256([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw "SHA-256 mismatch for $Path`n  expected $Expected`n  actual   $actual"
    }
    Write-Info "SHA-256 OK  $(Split-Path -Leaf $Path)"
}

# Clone (or reuse) a repo and check out an exact commit. Refuses any mismatch or local change.
function Get-PinnedGit([string]$Url, [string]$Dir, [string]$Commit) {
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) {
        Invoke-Checked 'git' @('clone', '--no-checkout', $Url, $Dir)
    }
    $origin = ((Invoke-Native 'git' @('-C', $Dir, 'remote', 'get-url', 'origin')) -join '').Trim()
    if ($origin -ne $Url) { throw "Unexpected origin for ${Dir}: $origin (expected $Url)" }
    [void](Invoke-Native 'git' @('-C', $Dir, 'cat-file', '-e', "$Commit^{commit}"))
    if ($LASTEXITCODE -ne 0) { Invoke-Checked 'git' @('-C', $Dir, 'fetch', 'origin', $Commit) }
    Invoke-Checked 'git' @('-C', $Dir, 'checkout', '--quiet', '--detach', $Commit)
    Assert-GitAt $Dir $Commit
}

function Assert-GitAt([string]$Dir, [string]$Commit) {
    $head = ((Invoke-Native 'git' @('-C', $Dir, 'rev-parse', 'HEAD')) -join '').Trim()
    if ($head -ne $Commit) { throw "Pin mismatch in ${Dir}: HEAD $head, expected $Commit" }
    $dirty = (Invoke-Native 'git' @('-C', $Dir, 'status', '--porcelain', '--untracked-files=no')) -join "`n"
    if ($dirty) { throw "Unexpected local changes in ${Dir}:`n$dirty" }
    Write-Info "pinned OK  $(Split-Path -Leaf $Dir) @ $($Commit.Substring(0, 10))"
}

# Simple name of a VALID Authenticode signer, or $null when unsigned / invalid.
function Get-ValidSigner([string]$Path) {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate) { return $null }
    return $sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
}

# True when the file starts with "MZ" (a Windows program or DLL), whatever its extension.
function Test-IsPortableExecutable([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $b = New-Object byte[] 2
        return ($stream.Read($b, 0, 2) -eq 2 -and $b[0] -eq 0x4D -and $b[1] -eq 0x5A)
    } finally { $stream.Dispose() }
}

function Enter-VsDevEnvironment {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Build Tools not found. Run 1-install-prerequisites.ps1 first.' }
    $vs = ((Invoke-Native $vswhere @('-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')) -join '').Trim()
    if (-not $vs) { throw 'MSVC x64 tools not found in Visual Studio Build Tools.' }
    Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
    Write-Info "MSVC environment: $vs"
    return $vs
}
