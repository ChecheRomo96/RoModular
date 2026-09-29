<#
.SYNOPSIS
Clones the RoModular repositories and configures a shared AI workspace.

.DESCRIPTION
Existing Git worktrees are verified and left unchanged. Missing repositories
are cloned recursively. Workspace-level adapters are installed for Codex,
Claude Code, and compatible tools without changing global credentials or
agent configuration.

.PARAMETER Root
Workspace root. Defaults to a RoModularWorkspace directory beside the
RoModular checkout, or reuses its initialized parent workspace.

.PARAMETER Manifest
Alternate directory|origin repository manifest.

.PARAMETER ForceConfig
Replace existing workspace agent adapters that differ from their templates.

.PARAMETER DryRun
Print planned actions without changing the filesystem.
#>

[CmdletBinding()]
param(
    [string]$Root = "",
    [string]$Manifest = "",
    [switch]$ForceConfig,
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
$WorkspaceAgentsTemplate = Join-Path $RoModularRoot ".romodular/workspace/AGENTS.md"
$WorkspaceClaudeTemplate = Join-Path $RoModularRoot ".romodular/workspace/CLAUDE.md"

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

if (-not (Test-Path -LiteralPath $WorkspaceAgentsTemplate -PathType Leaf)) {
    throw "Workspace AGENTS template not found: $WorkspaceAgentsTemplate"
}
if (-not (Test-Path -LiteralPath $WorkspaceClaudeTemplate -PathType Leaf)) {
    throw "Workspace CLAUDE template not found: $WorkspaceClaudeTemplate"
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
        if ($LASTEXITCODE -ne 0 -or $ActualOrigin.Trim() -ne $RepositoryOrigin) {
            $DisplayedOrigin = if ($ActualOrigin) { $ActualOrigin.Trim() } else { "<missing>" }
            Write-Error (
                "$RepositoryName has unexpected origin: $DisplayedOrigin; " +
                "expected: $RepositoryOrigin"
            ) -ErrorAction Continue
            $Failed = $true
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
        & git clone --recurse-submodules $RepositoryOrigin $RepositoryPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Clone failed for $RepositoryName" -ErrorAction Continue
            $Failed = $true
        }
    }
}

function Install-WorkspaceFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $DestinationExists = Test-Path -LiteralPath $Destination
    $DestinationIsFile = Test-Path -LiteralPath $Destination -PathType Leaf

    if ($DestinationExists -and -not $DestinationIsFile) {
        Write-Error "$Destination exists but is not a regular file" -ErrorAction Continue
        return $false
    }
    if ($DestinationIsFile -and
        ((Get-Content -LiteralPath $Destination -Raw) -ceq
         (Get-Content -LiteralPath $Source -Raw))) {
        Write-Host "configured: $DisplayName is current"
        return $true
    }
    if ($DestinationExists -and -not $ForceConfig) {
        Write-Error (
            "$Destination already exists and differs from the template; " +
            "rerun with -ForceConfig to replace it"
        ) -ErrorAction Continue
        return $false
    }
    if ($DryRun) {
        Write-Host "[dry-run] install $DisplayName"
        return $true
    }

    $DestinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Host "configured: $Destination"
    return $true
}

$WorkspaceAgents = Join-Path $WorkspaceRoot "AGENTS.md"
$WorkspaceClaude = Join-Path (Join-Path $WorkspaceRoot ".claude") "CLAUDE.md"

if (-not (Install-WorkspaceFile `
    -Source $WorkspaceAgentsTemplate `
    -Destination $WorkspaceAgents `
    -DisplayName "workspace AGENTS.md")) {
    $Failed = $true
}
if (-not (Install-WorkspaceFile `
    -Source $WorkspaceClaudeTemplate `
    -Destination $WorkspaceClaude `
    -DisplayName "workspace .claude/CLAUDE.md")) {
    $Failed = $true
}

$CodexCommand = Get-Command codex -ErrorAction SilentlyContinue
if ($null -ne $CodexCommand) {
    $CodexVersion = (& codex --version 2>$null)
    if ($LASTEXITCODE -ne 0) {
        $CodexVersion = "version unavailable"
    }
    Write-Host "Codex available: $CodexVersion"
    Write-Host "  launch: codex -C `"$WorkspaceRoot`""
}
else {
    Write-Host "Codex not found; workspace files were configured without installing it."
}

$ClaudeCommand = Get-Command claude -ErrorAction SilentlyContinue
if ($null -ne $ClaudeCommand) {
    $ClaudeVersion = (& claude --version 2>$null)
    if ($LASTEXITCODE -ne 0) {
        $ClaudeVersion = "version unavailable"
    }
    Write-Host "Claude Code available: $ClaudeVersion"
    Write-Host "  launch: Set-Location `"$WorkspaceRoot`"; claude"
}
else {
    Write-Host "Claude Code not found; workspace files were configured without installing it."
}

if ($Failed) {
    throw "Workspace setup completed with errors"
}

Write-Host "Workspace setup complete. Existing repositories were not updated."
