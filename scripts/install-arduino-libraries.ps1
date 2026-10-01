<#
.SYNOPSIS
Clones the RoModular Arduino libraries into an Arduino libraries folder.

.DESCRIPTION
Installs Foundation, DspCore and MCC, in dependency order, from the origins listed in
the workspace repository manifest. Existing clones with the expected origin
are left unchanged. Any other existing folder is refused unless -Force is set.

.PARAMETER Path
Arduino libraries folder, for example "$HOME\Documents\Arduino\libraries".

.PARAMETER IncludeLegacy
Also install MIDILAR (legacy, pending reconstruction).

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

# Runtime libraries in dependency order. MIDILAR is legacy and opt-in.
$Libraries = @("Foundation", "DspCore", "MCC")
if ($IncludeLegacy) {
    $Libraries += "MIDILAR"
}

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
foreach ($Library in $Libraries) {
    if (-not $Origins.ContainsKey($Library)) {
        Write-Error "$Library is missing from $Manifest" -ErrorAction Continue
        $Failed = $true
        continue
    }

    $Origin = $Origins[$Library]
    $LibraryPath = Join-Path $LibrariesRoot $Library

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
            Write-Host "present: $Library (left unchanged)"
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
        Write-Host "[dry-run] clone $Origin into $LibraryPath"
        continue
    }

    Write-Host "cloning: $Library"
    & git clone $Origin $LibraryPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Clone failed for $Library" -ErrorAction Continue
        $Failed = $true
    }
}

if ($Failed) {
    throw "Arduino library installation completed with errors"
}

Write-Host "Arduino libraries installed. Existing clones were not updated."
Write-Host "DspCore and MCC on Arduino AVR require -std=gnu++17 (see their READMEs)."
