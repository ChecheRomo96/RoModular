[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repositoryRoot "scripts/romodular.ps1"
$manifest = Join-Path $repositoryRoot ".romodular/workspace/repositories.txt"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("romodular-cli-" + [guid]::NewGuid())

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if (-not $line.Trim() -or $line.TrimStart().StartsWith("#")) { continue }
        $fields = $line -split '\|', 2
        $name = $fields[0].Trim()
        $origin = $fields[1].Trim()
        $repository = Join-Path $testRoot $name
        New-Item -ItemType Directory -Path $repository | Out-Null
        & git -C $repository init -q -b main
        & git -C $repository config user.email "romodular-cli-test@example.invalid"
        & git -C $repository config user.name "RoModular CLI test"
        New-Item -ItemType File -Path (Join-Path $repository "tracked.txt") | Out-Null
        & git -C $repository add tracked.txt
        & git -C $repository commit -qm "Initial fixture"
        & git -C $repository remote add origin $origin
    }

    Set-Content -LiteralPath (Join-Path $testRoot "Foundation/untracked.txt") -Value "dirty"
    Remove-Item -LiteralPath (Join-Path $testRoot "MIDILAR") -Recurse -Force

    $doctor = (& $cli doctor -Root $testRoot | Out-String)
    $status = (& $cli status -Root $testRoot | Out-String)
    if ($doctor -notmatch [regex]::Escape("workspace marker: absent (manifest layout accepted)")) { throw "doctor did not report the fixture layout" }
    if ($status -notmatch "Foundation: .*dirty=1 .*origin=ok .*upstream=none") { throw "status did not report the dirty repository" }
    if ($status -notmatch "(?m)^MIDILAR: missing$") { throw "status did not report the missing repository" }

    $before = (& git -C (Join-Path $testRoot "RoModular") rev-parse HEAD).Trim()
    $beforeBranch = (& git -C (Join-Path $testRoot "RoModular") branch --show-current).Trim()
    $beforeStatus = (& git -C (Join-Path $testRoot "RoModular") status --porcelain | Out-String)
    & $cli sync -DryRun -Root $testRoot | Out-Null
    $after = (& git -C (Join-Path $testRoot "RoModular") rev-parse HEAD).Trim()
    $afterBranch = (& git -C (Join-Path $testRoot "RoModular") branch --show-current).Trim()
    $afterStatus = (& git -C (Join-Path $testRoot "RoModular") status --porcelain | Out-String)
    if ($before -ne $after) { throw "sync --dry-run changed a repository" }
    if ($beforeBranch -ne $afterBranch) { throw "sync --dry-run changed the checked-out branch" }
    if ($beforeStatus -ne $afterStatus) { throw "sync --dry-run changed the worktree" }

    $syncRejected = $false
    try {
        & $cli sync -Root $testRoot *> $null
    }
    catch {
        $syncRejected = $true
    }
    if (-not $syncRejected) { throw "sync without -DryRun unexpectedly succeeded" }

    Write-Output "RoModular CLI PowerShell integration tests passed."
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
