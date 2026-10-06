<#
.SYNOPSIS
Clones the RoModular Arduino libraries into an Arduino libraries folder, or
brings existing clones up to date.

.DESCRIPTION
Installs CPSTL, Foundation, DspCore, MCC and MIDILAR, in dependency order, from the
origins listed in the workspace repository manifest. Existing clones with the
expected origin are fast-forwarded to the latest commit of their branch;
clones with local changes or diverged history are reported and left as they
are. Any other existing folder is refused unless -Force is set.

.PARAMETER Path
Arduino libraries folder, for example "$HOME\Documents\Arduino\libraries".

.PARAMETER IncludeLegacy
Accepted and ignored: MIDILAR is always installed.

.PARAMETER Force
Replace existing library folders that are not the expected clone.

.PARAMETER DryRun
Print planned actions without changing the filesystem.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Path,
    [switch]$IncludeLegacy,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RoModularRoot = Split-Path -Parent $PSScriptRoot
$Manifest = Join-Path $RoModularRoot ".romodular/workspace/repositories.txt"

# Runtime libraries in dependency order. CPSTL comes first: it is the base
# of the chain, and Foundation is planned to build on it.
$Libraries = @("CPSTL", "Foundation", "DspCore", "MCC", "MIDILAR")

# Branch to install when a clone may be on another one. MIDILAR clones made
# before 0.2.0 tracked `rebuild`; they are switched back to `main`.
$Branches = @{ "MIDILAR" = "main" }

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required but was not found on PATH"
}
if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
    throw "Repository manifest not found: $Manifest"
}

function Normalize-GitOrigin {
    param([Parameter(Mandatory = $true)][string]$Origin)

    $Normalized = $Origin.Trim().TrimEnd("/")
    return ($Normalized -replace '\.git$', '')
}

function Get-CurrentBranch {
    param([Parameter(Mandatory = $true)][string]$LibraryPath)

    $Current = (& git -C $LibraryPath symbolic-ref --quiet --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return "$Current".Trim()
}

# Fast-forwards a clean clone to the latest commit of its branch. Returns
# "updated", "skipped" or "failed".
function Update-Clone {
    param(
        [Parameter(Mandatory = $true)][string]$Library,
        [Parameter(Mandatory = $true)][string]$LibraryPath,
        [string]$Branch
    )

    $Status = (& git -C $LibraryPath status --porcelain)
    if ($Status) {
        Write-Warning "$Library has local changes; not updated"
        return "skipped"
    }
    if ($DryRun) {
        $Target = if ($Branch) { " to branch $Branch" } else { "" }
        Write-Host "[dry-run] update $Library$Target"
        return "updated"
    }
    & git -C $LibraryPath fetch --quiet origin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Fetch failed for $Library" -ErrorAction Continue
        return "failed"
    }
    $Current = Get-CurrentBranch -LibraryPath $LibraryPath
    if (-not $Branch) {
        $Branch = $Current
        if (-not $Branch) {
            Write-Warning "$Library is not on a branch; not updated"
            return "skipped"
        }
    }
    if ($Current -ne $Branch) {
        & git -C $LibraryPath checkout --quiet $Branch 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & git -C $LibraryPath checkout --quiet -b $Branch --track "origin/$Branch" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Cannot switch $Library to branch $Branch" -ErrorAction Continue
                return "failed"
            }
        }
    }
    & git -C $LibraryPath merge --quiet --ff-only "origin/$Branch" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Library has commits not on origin/$Branch; not updated"
        return "skipped"
    }
    $Head = (& git -C $LibraryPath rev-parse --short HEAD)
    Write-Host "updated: $Library ($Branch at $Head)"
    return "updated"
}

$Origins = @{}
foreach ($Line in Get-Content -LiteralPath $Manifest) {
    $Fields = $Line.Trim() -split '\|', 2
    if ($Fields.Count -eq 2 -and -not $Fields[0].StartsWith("#")) {
        $Origins[$Fields[0].Trim()] = $Fields[1].Trim()
    }
}

$LibrariesRoot = [System.IO.Path]::GetFullPath($Path)
Write-Host "Arduino libraries: $LibrariesRoot"
if (-not $DryRun) {
    New-Item -ItemType Directory -Path $LibrariesRoot -Force | Out-Null
}

$Failed = $false
$Skipped = $false
foreach ($Library in $Libraries) {
    if (-not $Origins.ContainsKey($Library)) {
        Write-Error "$Library is missing from $Manifest" -ErrorAction Continue
        $Failed = $true
        continue
    }

    $Origin = $Origins[$Library]
    $LibraryPath = Join-Path $LibrariesRoot $Library
    $Branch = if ($Branches.ContainsKey($Library)) { $Branches[$Library] } else { "" }
    $BranchNote = if ($Branch) { " (branch $Branch)" } else { "" }

    if (Test-Path -LiteralPath $LibraryPath) {
        $ActualOrigin = $null
        if (Test-Path -LiteralPath (Join-Path $LibraryPath ".git")) {
            $ActualOrigin = (& git -C $LibraryPath remote get-url origin 2>$null)
            if ($LASTEXITCODE -ne 0) {
                $ActualOrigin = $null
            }
        }
        if ($ActualOrigin -and
            (Normalize-GitOrigin -Origin $ActualOrigin) -eq (Normalize-GitOrigin -Origin $Origin)) {
            switch (Update-Clone -Library $Library -LibraryPath $LibraryPath -Branch $Branch) {
                "skipped" { $Skipped = $true }
                "failed" { $Failed = $true }
            }
            continue
        }
        if (-not $Force) {
            Write-Error (
                "$LibraryPath already exists and is not a clone of $Origin; " +
                "rerun with -Force to replace it"
            ) -ErrorAction Continue
            $Failed = $true
            continue
        }
        if ($DryRun) {
            Write-Host "[dry-run] replace $LibraryPath"
            continue
        }
        Remove-Item -LiteralPath $LibraryPath -Recurse -Force
    }
    elseif ($DryRun) {
        Write-Host "[dry-run] clone $Origin$BranchNote into $LibraryPath"
        continue
    }

    Write-Host "cloning: $Library$BranchNote"
    if ($Branch) {
        & git clone --branch $Branch $Origin $LibraryPath
    }
    else {
        & git clone $Origin $LibraryPath
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Clone failed for $Library" -ErrorAction Continue
        $Failed = $true
    }
}

if ($Failed) {
    throw "Arduino library installation completed with errors"
}

if ($Skipped) {
    Write-Host "Arduino libraries installed; the clones warned about above were not updated."
}
else {
    Write-Host "Arduino libraries installed and up to date."
}
Write-Host "DspCore and MIDILAR on Arduino AVR require -std=gnu++17 (see their READMEs);"
Write-Host "CPSTL, Foundation and MCC build with the stock C++11 core."
