param(
  [Parameter(Mandatory=$true)][ValidateSet("general","compute","memory")][string]$Profile,
  [Parameter(Mandatory=$true)][ValidateSet("S1","S2","S3")][string]$Scenario,
  [int]$Repeat = 3
)

$ErrorActionPreference = "Stop"

function Get-RepoPythonExe([string]$repoRoot) {
  $venvPy = Join-Path $repoRoot ".venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $venvPy) { return (Resolve-Path -LiteralPath $venvPy).Path }
  return "python"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot
$pythonExe = Get-RepoPythonExe $repoRoot.Path

# Read scenario settings from YAML via python (consistent with analyze pipeline)
$tmp = New-TemporaryFile
try {
  & $pythonExe -c @"
import sys, yaml
from pathlib import Path

sc = sys.argv[1]
out = Path(sys.argv[2])
m = yaml.safe_load(Path('experiments/matrix.yaml').read_text(encoding='utf-8'))
if 'scenarios' not in m or sc not in m['scenarios']:
    raise SystemExit(f'Scenario not found: {sc}')
s = m['scenarios'][sc]
out.write_text(
    str(int(s['concurrency'])) + '\n' + str(int(s['duration_s'])) + '\n' + '\n'.join(s['paths']) + '\n',
    encoding='utf-8',
)
"@ $Scenario $tmp.FullName
  if ($LASTEXITCODE -ne 0) { throw "Failed to read experiments/matrix.yaml via python (exit=$LASTEXITCODE)." }

  $lines = Get-Content $tmp.FullName
} finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $tmp.FullName
}

$concurrency = [int]$lines[0]
$durationS = [int]$lines[1]
$paths = $lines[2..($lines.Count-1)] | Where-Object { $_ -and $_.Trim().Length -gt 0 }

# Determine the compose network to run the load generator in.
$ngx = docker compose ps -q nginx
if (-not $ngx) { throw "nginx container not running. Run scripts/up_profile.ps1 first." }
$net = docker inspect $ngx --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}'
if (-not $net) { throw "Failed to detect docker network for nginx container." }

$runId = "$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss'))Z_${Profile}_${Scenario}"
$outDir = Join-Path "experiments/results" $runId
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

@"
run_id=$runId
profile=$Profile
scenario=$Scenario
concurrency=$concurrency
duration_s=$durationS
loadgen=docker_httpd_ab
target=http://nginx
network=$net
"@ | Set-Content -Encoding UTF8 (Join-Path $outDir "meta.txt")

$nRequests = $durationS * $concurrency

for ($i = 1; $i -le $Repeat; $i++) {
  foreach ($p in $paths) {
    $url = "http://nginx$p"
    $safePath = ($p -replace "[^a-zA-Z0-9]", "_").Trim("_")
    if (-not $safePath) { $safePath = "root" }
    $outFile = Join-Path $outDir "ab_${safePath}_rep${i}.txt"

    Write-Host "Running docker ab: $url (c=$concurrency, n=$nRequests) -> $outFile"

    # Use Start-Process redirection so PowerShell 5.x does not treat stderr as terminating errors.
    $args = @(
      "run", "--rm",
      "--network", $net,
      "httpd:2.4-alpine",
      "ab", "-k",
      # Fail fast instead of hanging forever on socket stalls.
      "-s", 30,
      "-c", $concurrency,
      "-t", $durationS,
      $url
    )
    $errFile = "$outFile.err"
    try {
      $proc = Start-Process -FilePath "docker.exe" -ArgumentList $args -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
      if (Test-Path -LiteralPath $errFile) {
        Add-Content -LiteralPath $outFile -Value (Get-Content -LiteralPath $errFile -Raw) -Encoding UTF8
      }
      if ($proc.ExitCode -ne 0) {
        throw "docker ab failed (exit=$($proc.ExitCode)) for URL: $url"
      }
    } finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $errFile
    }
  }
}

Write-Host "Saved results to $outDir"

