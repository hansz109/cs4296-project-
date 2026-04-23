param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("general","compute","memory")]
  [string]$Profile
)

$ErrorActionPreference = "Stop"

function Set-ProfileEnv($profile) {
  switch ($profile) {
    "general" {
      $env:PROFILE_DB_CPUS  = "0.5"
      $env:PROFILE_DB_MEM   = "1g"
      $env:PROFILE_WP_CPUS  = "1.0"
      $env:PROFILE_WP_MEM   = "2g"
      $env:PROFILE_NGX_CPUS = "0.5"
      $env:PROFILE_NGX_MEM  = "512m"
    }
    "compute" {
      $env:PROFILE_DB_CPUS  = "1.0"
      $env:PROFILE_DB_MEM   = "1g"
      $env:PROFILE_WP_CPUS  = "3.0"
      $env:PROFILE_WP_MEM   = "2g"
      $env:PROFILE_NGX_CPUS = "1.0"
      $env:PROFILE_NGX_MEM  = "512m"
    }
    "memory" {
      $env:PROFILE_DB_CPUS  = "0.5"
      $env:PROFILE_DB_MEM   = "4g"
      $env:PROFILE_WP_CPUS  = "1.0"
      $env:PROFILE_WP_MEM   = "10g"
      $env:PROFILE_NGX_CPUS = "0.5"
      $env:PROFILE_NGX_MEM  = "1g"
    }
  }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

Set-ProfileEnv $Profile

docker compose pull
docker compose up -d

Write-Host "Started profile '$Profile'. Open: http://localhost/"
docker compose ps

