$ErrorActionPreference = "Stop"

param(
  [Parameter(Mandatory=$true)][ValidateSet("general","compute","memory")][string]$Profile,
  [Parameter(Mandatory=$true)][ValidateSet("S1","S2","S3")][string]$Scenario,
  [int]$Repeat = 3,
  [string]$BaseUrl = "http://localhost"
)

if (-not (Get-Command ab.exe -ErrorAction SilentlyContinue)) {
  throw "ab.exe not found. Run scripts/install_ab_windows.ps1 (or install ApacheBench manually)."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

# Read scenario settings from YAML via python (consistent with analyze pipeline)
$tmp = New-TemporaryFile
python - <<'PY' $Scenario $tmp.FullName
import sys, yaml
from pathlib import Path

sc = sys.argv[1]
out = Path(sys.argv[2])
m = yaml.safe_load(Path("experiments/matrix.yaml").read_text(encoding="utf-8"))
if "scenarios" not in m or sc not in m["scenarios"]:
    raise SystemExit(f"Scenario not found: {sc}")
s = m["scenarios"][sc]
out.write_text(f"{s['concurrency']}\n{s['duration_s']}\n" + "\n".join(s["paths"]) + "\n", encoding="utf-8")
PY

$lines = Get-Content $tmp.FullName
$concurrency = [int]$lines[0]
$durationS = [int]$lines[1]
$paths = $lines[2..($lines.Count-1)] | Where-Object { $_ -and $_.Trim().Length -gt 0 }

$runId = "$(Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ')_${Profile}_${Scenario}"
$outDir = Join-Path "experiments/results" $runId
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

@"
run_id=$runId
profile=$Profile
base_url=$BaseUrl
scenario=$Scenario
concurrency=$concurrency
duration_s=$durationS
"@ | Set-Content -Encoding UTF8 (Join-Path $outDir "meta.txt")

$nRequests = $durationS * $concurrency

for ($i=1; $i -le $Repeat; $i++) {
  foreach ($p in $paths) {
    $url = "$BaseUrl$p"
    $safePath = ($p -replace "[^a-zA-Z0-9]", "_")
    $outFile = Join-Path $outDir "ab_${safePath}_rep${i}.txt"
    Write-Host "Running ab: $url (c=$concurrency, n=$nRequests) -> $outFile"
    & ab.exe -k -c $concurrency -n $nRequests $url 1> $outFile 2>&1
  }
}

Write-Host "Saved results to $outDir"

