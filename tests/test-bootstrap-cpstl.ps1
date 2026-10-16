$ErrorActionPreference = "Stop"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ("bootstrap-cpstl-" + [guid]::NewGuid())
$Upstream = Join-Path $Fixture "upstream"
$Manifest = Join-Path $Fixture "repositories.txt"
New-Item -ItemType Directory $Fixture | Out-Null

function Invoke-FixtureGit {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $args" }
}
Invoke-FixtureGit init -q -b main $Upstream
Invoke-FixtureGit -C $Upstream -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m initial
Set-Content $Manifest "CPSTL|$($Upstream.Replace('\', '/'))"

foreach ($Mode in @("powershell", "shell")) {
    $Workspace = Join-Path $Fixture $Mode
    $Checkout = Join-Path $Workspace "CPSTL"
    function Bootstrap([switch]$Preview, [switch]$ExpectFailure) {
        $Failed = $false
        if ($Mode -eq "powershell") {
            try {
                & "$RepositoryRoot/scripts/bootstrap-workspace.ps1" -Root $Workspace -Manifest $Manifest -DryRun:$Preview
            }
            catch { $Failed = $true }
        }
        else {
            $Options = @("--root", $Workspace, "--manifest", $Manifest)
            if ($Preview) { $Options += "--dry-run" }
            & sh "$RepositoryRoot/scripts/bootstrap-workspace.sh" @Options
            $Failed = $LASTEXITCODE -ne 0
        }
        if ($Failed -ne [bool]$ExpectFailure) { throw "Unexpected bootstrap result in $Mode" }
    }
    Bootstrap
    $Initial = Invoke-FixtureGit -C $Checkout rev-parse HEAD
    Invoke-FixtureGit -C $Upstream -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m advance
    Bootstrap -Preview
    if ((Invoke-FixtureGit -C $Checkout rev-parse HEAD) -ne $Initial) { throw "Dry-run changed HEAD" }
    Bootstrap
    if ((Invoke-FixtureGit -C $Checkout rev-parse HEAD) -ne (Invoke-FixtureGit -C $Upstream rev-parse HEAD)) { throw "CPSTL was not updated" }
    Set-Content (Join-Path $Checkout "local.txt") "preserve local work"
    Bootstrap -ExpectFailure
    if ((Get-Content (Join-Path $Checkout "local.txt")) -ne "preserve local work") { throw "Local work changed" }
    Invoke-FixtureGit -C $Checkout add local.txt
    Invoke-FixtureGit -C $Checkout -c user.name=Test -c user.email=test@example.com commit -q -m local
    $LocalHead = Invoke-FixtureGit -C $Checkout rev-parse HEAD
    Bootstrap -ExpectFailure
    if ((Invoke-FixtureGit -C $Checkout rev-parse HEAD) -ne $LocalHead) { throw "Local commits changed" }
    Invoke-FixtureGit -C $Checkout checkout -q --detach
    Bootstrap -ExpectFailure
}
Write-Host "CPSTL bootstrap regression checks passed for PowerShell and shell. Fixtures: $Fixture"
$global:LASTEXITCODE = 0
