[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("doctor", "status", "sync")][string]$Command,
    [string]$Root = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $repoRoot ".romodular/workspace/repositories.txt"
if (-not $Root) { $Root = Split-Path -Parent $repoRoot }
$workspaceRoot = [IO.Path]::GetFullPath($Root)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git is required but was not found on PATH" }

function Get-Repositories {
    Get-Content -LiteralPath $manifest | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $fields = $line -split '\|', 2
            [PSCustomObject]@{ Name = $fields[0].Trim(); Origin = $fields[1].Trim() }
        }
    }
}
function Normalize-Origin([string]$Origin) {
    return (($Origin.TrimEnd("/")) -replace '\.git$', '')
}
function Show-Status {
    foreach ($repository in Get-Repositories) {
        $name = $repository.Name
        $path = Join-Path $workspaceRoot $name
        & git -C $path rev-parse --is-inside-work-tree *> $null
        if ($LASTEXITCODE -ne 0) { Write-Output "$name`: missing"; continue }
        $actualOrigin = (& git -C $path remote get-url origin 2>$null).Trim()
        $originStatus = if ($actualOrigin -and (Normalize-Origin $actualOrigin) -eq (Normalize-Origin $repository.Origin)) { "ok" } else { "mismatch" }
        $branch = (& git -C $path branch --show-current).Trim(); if (-not $branch) { $branch = "detached" }
        $shortSha = (& git -C $path rev-parse --short HEAD).Trim()
        $dirty = @(& git -C $path status --porcelain).Count
        $upstream = (& git -C $path rev-parse --abbrev-ref '@{upstream}' 2>$null).Trim()
        if (-not $upstream) { $upstream = "none" }
        $drift = (& git -C $path rev-list --left-right --count '@{upstream}...HEAD' 2>$null).Trim()
        if ($drift -match '^([0-9]+)\s+([0-9]+)$') { $drift = "behind=$($Matches[1]) ahead=$($Matches[2]) (cached)" } else { $drift = "behind/ahead=unknown (cached)" }
        Write-Output "$name`: ref=$branch sha=$shortSha dirty=$dirty origin=$originStatus upstream=$upstream $drift"
    }
}
switch ($Command) {
    "doctor" {
        Write-Output "RoModular workspace: $workspaceRoot"
        if (Test-Path -LiteralPath (Join-Path $workspaceRoot ".romodular-workspace")) { Write-Output "workspace marker: present" } else { Write-Output "workspace marker: absent (manifest layout accepted)" }
        Show-Status
        foreach ($tool in "cmake", "ninja", "doxygen") {
            $availability = if (Get-Command $tool -ErrorAction SilentlyContinue) { "available" } else { "unavailable" }
            Write-Output "$tool`: $availability"
        }
    }
    "status" { Show-Status }
    "sync" { if (-not $DryRun) { throw "sync is preview-only in this release; rerun with -DryRun" }; Write-Output "Sync plan only: no repositories changed. A future release may execute only clean, fast-forward updates."; Show-Status }
}
