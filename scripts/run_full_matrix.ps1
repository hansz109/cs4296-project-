param(
  [ValidateSet("general","compute","memory")]
  [string[]]$Profiles = @("general","compute","memory"),

  [ValidateSet("S1","S2","S3")]
  [string[]]$Scenarios = @("S1","S2","S3"),

  [int]$Repeat = 3,
  [string]$BaseUrl = "http://localhost",
  [int]$HttpWaitSeconds = 300,
  [switch]$SkipPullOnProfileSwitch
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

function Wait-HttpOk([string]$url) {
  $deadline = (Get-Date).AddSeconds($HttpWaitSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      & curl.exe -fsS --connect-timeout 2 -m 10 -o NUL $url 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { return }
    } catch {}
    Start-Sleep -Seconds 2
  }
  throw "Timed out waiting for HTTP OK: $url (${HttpWaitSeconds}s)."
}

foreach ($p in $Profiles) {
  Write-Host "=== Profile: $p ==="
  if ($SkipPullOnProfileSwitch) {
    & (Join-Path $PSScriptRoot "up_profile.ps1") -Profile $p -SkipPull
  } else {
    & (Join-Path $PSScriptRoot "up_profile.ps1") -Profile $p
  }

  Wait-HttpOk ($BaseUrl.TrimEnd("/") + "/")

  foreach ($s in $Scenarios) {
    Write-Host "--- Scenario: $s ---"
    # Prefer dockerized ab (more stable than WSL<->Windows networking).
    & (Join-Path $PSScriptRoot "run_bench_docker.ps1") -Profile $p -Scenario $s -Repeat $Repeat
  }
}

Write-Host "All requested runs completed."
