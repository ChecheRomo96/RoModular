<#
.SYNOPSIS
Clones the RoModular Arduino libraries into an Arduino libraries folder, or
brings existing clones up to date.

.DESCRIPTION
Installs released CPSTL, Foundation, DspCore, MCC and MIDILAR in dependency order from
the immutable tags in the release-pins manifest. -UseHead is the explicit
development opt-in: it installs the main branches and includes DspCore.
Existing clones with local changes are reported and left as they are. Any
other existing folder is refused unless -Force is set.

.PARAMETER Path
Arduino libraries folder, for example "$HOME\Documents\Arduino\libraries".

.PARAMETER IncludeLegacy
Accepted and ignored: MIDILAR is always installed.

.PARAMETER Force
Replace existing library folders that are not the expected clone.

.PARAMETER DryRun
Print planned actions without changing the filesystem.

.PARAMETER UseHead
Install development heads instead of immutable release tags.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Path,
    [switch]$IncludeLegacy,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$UseHead
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RoModularRoot = Split-Path -Parent $PSScriptRoot
$Manifest = Join-Path $RoModularRoot ".romodular/workspace/repositories.txt"
$PinsManifest = Join-Path $RoModularRoot ".romodular/workspace/release-pins.txt"

# Released Arduino libraries in dependency order.
$StableLibraries = @("CPSTL", "Foundation", "DspCore", "MCC", "MIDILAR")
$HeadLibraries = @("CPSTL", "Foundation", "DspCore", "MCC", "MIDILAR")

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required but was not found on PATH"
}
if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
    throw "Repository manifest not found: $Manifest"
}
if (-not (Test-Path -LiteralPath $PinsManifest -PathType Leaf)) {
    throw "Release pins manifest not found: $PinsManifest"
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

# Moves a clean clone to an immutable tag, or fast-forwards it to a development
# branch when -UseHead is selected. Returns "updated", "skipped" or "failed".
function Update-Clone {
    param(
        [Parameter(Mandatory = $true)][string]$Library,
        [Parameter(Mandatory = $true)][string]$LibraryPath,
        [Parameter(Mandatory = $true)][string]$Reference
    )

    $Status = (& git -C $LibraryPath status --porcelain)
    if ($Status) {
        Write-Warning "$Library has local changes; not updated"
        return "skipped"
    }
    if ($DryRun) {
        Write-Host "[dry-run] update $Library to $Reference"
        return "updated"
    }
    & git -C $LibraryPath fetch --quiet --tags origin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Fetch failed for $Library" -ErrorAction Continue
        return "failed"
    }
    if (-not $UseHead) {
        & git -C $LibraryPath rev-parse --verify --quiet "refs/tags/$Reference^{commit}" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Tag $Reference was not found for $Library" -ErrorAction Continue
            return "failed"
        }
        & git -C $LibraryPath checkout --quiet --detach $Reference | Out-Null
        $Head = (& git -C $LibraryPath rev-parse --short HEAD)
        Write-Host "pinned: $Library ($Reference at $Head)"
    }
    else {
        & git -C $LibraryPath checkout --quiet $Reference 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & git -C $LibraryPath checkout --quiet -b $Reference --track "origin/$Reference" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Cannot switch $Library to branch $Reference" -ErrorAction Continue
                return "failed"
            }
        }
        & git -C $LibraryPath merge --quiet --ff-only "origin/$Reference" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "$Library has commits not on origin/$Reference; not updated"
            return "skipped"
        }
        $Head = (& git -C $LibraryPath rev-parse --short HEAD)
        Write-Host "updated: $Library ($Reference at $Head)"
    }
    return "updated"
}

$Origins = @{}
foreach ($Line in Get-Content -LiteralPath $Manifest) {
    $Fields = $Line.Trim() -split '\|', 2
    if ($Fields.Count -eq 2 -and -not $Fields[0].StartsWith("#")) {
        $Origins[$Fields[0].Trim()] = $Fields[1].Trim()
    }
}

$Pins = @{}
foreach ($Line in Get-Content -LiteralPath $PinsManifest) {
    $Fields = $Line.Trim() -split '\|', 2
    if ($Fields.Count -eq 2 -and -not $Fields[0].StartsWith("#")) {
        $Pins[$Fields[0].Trim()] = $Fields[1].Trim()
    }
}

$Libraries = if ($UseHead) { $HeadLibraries } else { $StableLibraries }
$Mode = if ($UseHead) { "development heads" } else { "release pins" }

$LibrariesRoot = [System.IO.Path]::GetFullPath($Path)
Write-Host "Arduino libraries: $LibrariesRoot ($Mode)"
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
    if ($UseHead) {
        $Reference = "main"
    }
    elseif ($Pins.ContainsKey($Library)) {
        $Reference = $Pins[$Library]
    }
    else {
        Write-Error "$Library is missing from $PinsManifest" -ErrorAction Continue
        $Failed = $true
        continue
    }
    $ReferenceNote = " ($Reference)"

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
            switch (Update-Clone -Library $Library -LibraryPath $LibraryPath -Reference $Reference) {
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
        Write-Host "[dry-run] clone $Origin$ReferenceNote into $LibraryPath"
        continue
    }

    Write-Host "cloning: $Library$ReferenceNote"
    & git clone --branch $Reference $Origin $LibraryPath
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
    Write-Host "Arduino libraries installed and at the requested references."
}
Write-Host "Installed libraries support stock Arduino C++11 source builds; see each README for non-Arduino requirements."
