<#
.SYNOPSIS
Clones the RoModular repositories into a shared workspace.

.DESCRIPTION
Existing Git worktrees are verified. Clean CPSTL main checkouts are
fast-forwarded; other existing repositories are left unchanged. Missing
repositories are cloned recursively.

.PARAMETER Root
Workspace root. Defaults to a RoModularWorkspace directory beside the
RoModular checkout, or reuses its initialized parent workspace.

.PARAMETER Manifest
Alternate directory|origin repository manifest.

.PARAMETER DryRun
Print planned actions without changing the filesystem.
#>

[CmdletBinding()]
param(
    [string]$Root = "",
    [string]$Manifest = "",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RoModularRoot = Split-Path -Parent $PSScriptRoot
$RoModularParent = Split-Path -Parent $RoModularRoot
$WorkspaceMarkerName = ".romodular-workspace"
$ParentWorkspaceMarker = Join-Path $RoModularParent $WorkspaceMarkerName
$DefaultWorkspaceRoot = if (Test-Path -LiteralPath $ParentWorkspaceMarker -PathType Leaf) {
    $RoModularParent
}
else {
    Join-Path $RoModularParent "RoModularWorkspace"
}
$DefaultManifest = Join-Path $RoModularRoot ".romodular/workspace/repositories.txt"

if ([string]::IsNullOrWhiteSpace($Root)) {
    if ([string]::IsNullOrWhiteSpace($env:ROMODULAR_WORKSPACE_ROOT)) {
        $Root = $DefaultWorkspaceRoot
    }
    else {
        $Root = $env:ROMODULAR_WORKSPACE_ROOT
    }
}

if ([string]::IsNullOrWhiteSpace($Manifest)) {
    $Manifest = $DefaultManifest
}

$WorkspaceRoot = [System.IO.Path]::GetFullPath($Root)
$Manifest = [System.IO.Path]::GetFullPath($Manifest)

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

Write-Host "RoModular workspace: $WorkspaceRoot"

if ($DryRun) {
    Write-Host "[dry-run] create workspace directory if missing"
}
else {
    New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
}

$Failed = $false
$WorkspaceMarker = Join-Path $WorkspaceRoot $WorkspaceMarkerName

if ((Test-Path -LiteralPath $WorkspaceMarker) -and
    -not (Test-Path -LiteralPath $WorkspaceMarker -PathType Leaf)) {
    Write-Error "$WorkspaceMarker exists but is not a regular file" -ErrorAction Continue
    $Failed = $true
}
elseif ($DryRun) {
    Write-Host "[dry-run] create workspace marker"
}
elseif (-not (Test-Path -LiteralPath $WorkspaceMarker)) {
    Set-Content -LiteralPath $WorkspaceMarker -Value "RoModular workspace format 1"
}

foreach ($Line in Get-Content -LiteralPath $Manifest) {
    $TrimmedLine = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($TrimmedLine) -or $TrimmedLine.StartsWith("#")) {
        continue
    }

    $Fields = $TrimmedLine -split '\|', 2
    if ($Fields.Count -ne 2 -or [string]::IsNullOrWhiteSpace($Fields[1])) {
        Write-Error "Invalid repository manifest entry: $Line" -ErrorAction Continue
        $Failed = $true
        continue
    }

    $RepositoryName = $Fields[0].Trim()
    $RepositoryOrigin = $Fields[1].Trim()
    $RepositoryPath = Join-Path $WorkspaceRoot $RepositoryName

    if (Test-Path -LiteralPath $RepositoryPath) {
        & git -C $RepositoryPath rev-parse --is-inside-work-tree *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "$RepositoryPath exists but is not a Git worktree" -ErrorAction Continue
            $Failed = $true
            continue
        }

        $ActualOrigin = (& git -C $RepositoryPath remote get-url origin 2>$null)
        $NormalizedActualOrigin = if ($ActualOrigin) {
            Normalize-GitOrigin -Origin $ActualOrigin
        }
        else {
            ""
        }
        $NormalizedExpectedOrigin = Normalize-GitOrigin -Origin $RepositoryOrigin
        if ($LASTEXITCODE -ne 0 -or
            $NormalizedActualOrigin -ne $NormalizedExpectedOrigin) {
            $DisplayedOrigin = if ($ActualOrigin) { $ActualOrigin.Trim() } else { "<missing>" }
            Write-Error (
                "$RepositoryName has unexpected origin: $DisplayedOrigin; " +
                "expected: $RepositoryOrigin"
            ) -ErrorAction Continue
            $Failed = $true
            continue
        }

        if ($RepositoryName -eq "CPSTL") {
            $Status = & git -C $RepositoryPath status --porcelain
            if ($LASTEXITCODE -ne 0) { throw "Cannot inspect CPSTL status" }
            $Branch = & git -C $RepositoryPath symbolic-ref --quiet --short HEAD
            if ($LASTEXITCODE -ne 0 -or $Branch -ne "main" -or $Status) {
                throw "CPSTL must be clean and on main to update; preserve local work before retrying"
            }
            if ($DryRun) {
                Write-Host "[dry-run] fetch CPSTL main and fast-forward to origin/main"
                continue
            }
            & git -C $RepositoryPath fetch origin "+refs/heads/main:refs/remotes/origin/main"
            if ($LASTEXITCODE -ne 0) { throw "Fetch failed for CPSTL" }
            & git -C $RepositoryPath merge-base --is-ancestor HEAD origin/main
            if ($LASTEXITCODE -ne 0) { throw "CPSTL has local commits; cannot update to origin/main" }
            & git -C $RepositoryPath merge --ff-only origin/main
            if ($LASTEXITCODE -ne 0) { throw "Fast-forward failed for CPSTL" }
            Write-Host "updated: CPSTL (origin/main)"
            continue
        }
        Write-Host "present: $RepositoryName (left unchanged)"
        continue
    }

    if ($DryRun) {
        Write-Host "[dry-run] clone $RepositoryOrigin into $RepositoryPath"
    }
    else {
        Write-Host "cloning: $RepositoryName"
        $CloneOptions = @("--recurse-submodules")
        if ($RepositoryName -eq "CPSTL") { $CloneOptions += @("--branch", "main") }
        & git clone @CloneOptions $RepositoryOrigin $RepositoryPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Clone failed for $RepositoryName" -ErrorAction Continue
            $Failed = $true
        }
    }
}

if ($Failed) {
    throw "Workspace setup completed with errors"
}

Write-Host "Workspace setup complete. CPSTL tracks origin/main; other existing repositories were not updated."
