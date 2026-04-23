param(
  [Parameter(Mandatory=$true)][ValidateSet("general","compute","memory")][string]$Profile,
  [Parameter(Mandatory=$true)][ValidateSet("S1","S2","S3")][string]$Scenario,
  [int]$Repeat = 3,
  [string]$BaseUrl = "http://localhost"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot
New-Item -ItemType Directory -Force -Path "experiments/results" | Out-Null

# Ensure ab exists in WSL
try {
  wsl bash -lc "command -v ab >/dev/null 2>&1"
} catch {
  throw "ab not found in WSL. Run scripts\\install_ab_wsl.ps1 first."
}

# Scenario settings (kept in sync with experiments/matrix.yaml)
switch ($Scenario) {
  "S1" { $concurrency = 10;  $durationS = 180; $paths = @("/", "/?p=1") }
  "S2" { $concurrency = 50;  $durationS = 300; $paths = @("/", "/?p=1") }
  "S3" { $concurrency = 100; $durationS = 300; $paths = @("/", "/?p=1") }
}

$runId = "$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))_${Profile}_${Scenario}"
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

# Collect docker stats during this scenario (best-effort)
$statsPath = Join-Path $outDir "docker_stats.csv"
"timestamp_utc,container_name,cpu_percent,mem_usage,mem_percent,net_io,block_io,pids" | Set-Content -Encoding UTF8 $statsPath
$endTs = (Get-Date).ToUniversalTime().AddSeconds($durationS + 30)
$statsJob = Start-Job -ScriptBlock {
  param($statsPath, $endTs)
  while ((Get-Date).ToUniversalTime() -lt $endTs) {
    try {
      $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
      $lines = docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}},{{.PIDs}}"
      foreach ($line in $lines) {
        Add-Content -Encoding UTF8 $statsPath "$ts,$line"
      }
    } catch {
      # ignore
    }
    Start-Sleep -Seconds 1
  }
} -ArgumentList $statsPath, $endTs

for ($i=1; $i -le $Repeat; $i++) {
  foreach ($p in $paths) {
    $url = "$BaseUrl$p"
    $safePath = ($p -replace "[^a-zA-Z0-9]", "_")
    $outFile = Join-Path $outDir "ab_${safePath}_rep${i}.txt"
    Write-Host "Running WSL ab: $url (c=$concurrency, n=$nRequests) -> $outFile"
    $outText = wsl bash -lc "ab -k -c $concurrency -n $nRequests '$url' 2>&1" | Out-String
    $outText | Set-Content -Encoding UTF8 $outFile
  }
}

if ($statsJob) {
  try { Stop-Job $statsJob -ErrorAction SilentlyContinue } catch {}
  try { Remove-Job $statsJob -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host "Saved results to $outDir"

