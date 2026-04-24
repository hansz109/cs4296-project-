param(
  [Parameter(Mandatory=$true)][ValidateSet("general","compute","memory")][string]$Profile,
  [Parameter(Mandatory=$true)][ValidateSet("S1","S2","S3")][string]$Scenario,
  [int]$Repeat = 3,
  [string]$BaseUrl = "http://localhost",
  [int]$HttpWaitSeconds = 300
)

$ErrorActionPreference = "Stop"

function Get-RepoPythonExe([string]$repoRoot) {
  $venvPy = Join-Path $repoRoot ".venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $venvPy) { return (Resolve-Path -LiteralPath $venvPy).Path }
  return "python"
}

function Test-Ipv4([string]$s) {
  return ($s -match '^\d{1,3}(\.\d{1,3}){3}$')
}

function Invoke-WslStdout([string]$bashLc) {
  # Avoid PowerShell 5.x treating native stderr as terminating errors when $ErrorActionPreference is Stop.
  # NOTE: Start-Process -ArgumentList must be passed the way wsl.exe expects on Windows; a single
  # `-lc "<script>"` argument is significantly more reliable than multiple argv tokens.
  $tmp = [IO.Path]::GetTempFileName()
  $tmpErr = "$tmp.err"
  try {
    $p = Start-Process -FilePath "wsl.exe" -ArgumentList "bash -lc `"$bashLc`"" -Wait -PassThru -NoNewWindow `
      -RedirectStandardOutput $tmp -RedirectStandardError $tmpErr
    $out = [IO.File]::ReadAllText($tmp)
    if ([IO.File]::Exists($tmpErr)) {
      $err = [IO.File]::ReadAllText($tmpErr)
      if ($err) { $out = ($out + "`n" + $err) }
    }
    return @{ ExitCode = $p.ExitCode; Text = $out }
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmp, $tmpErr
  }
}

function Get-WslHostIp {
  # On WSL2, /etc/resolv.conf nameserver is typically the Windows host IP reachable from WSL.
  # Use awk to avoid brittle quoting through Start-Process/wsl argv layers.
  $bashLc = 'awk ''/^nameserver/ {print $2; exit}'' /etc/resolv.conf'
  for ($t = 0; $t -lt 8; $t++) {
    $r = Invoke-WslStdout $bashLc
    $m = [regex]::Match($r.Text, '\b\d{1,3}(\.\d{1,3}){3}\b')
    if ($m.Success -and (Test-Ipv4 $m.Value)) { return $m.Value }
    Start-Sleep -Seconds (2 + $t)
  }
  throw "Failed to detect a valid Windows host IPv4 from WSL /etc/resolv.conf after retries."
}

function Resolve-BaseUrlForWsl([string]$url) {
  $u = [Uri]$url
  $hostName = $u.Host
  if ($hostName -eq "localhost" -or $hostName -eq "127.0.0.1") {
    $winIp = Get-WslHostIp
    $builder = New-Object System.UriBuilder $u
    $builder.Host = $winIp
    return $builder.Uri.AbsoluteUri.TrimEnd("/")
  }
  return $url.TrimEnd("/")
}

function Wait-HttpOk([string]$url) {
  $deadline = (Get-Date).AddSeconds($HttpWaitSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      # Validate Docker Desktop port publishing from Windows (localhost is the reliable probe here).
      & curl.exe -fsS --connect-timeout 2 -m 10 -o NUL $url 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { return }
    } catch {}
    Start-Sleep -Seconds 2
  }
  throw "Timed out waiting for HTTP OK: $url (${HttpWaitSeconds}s)."
}

function Escape-BashSingleQuoted([string]$s) {
  # Wrap $s in bash-safe single quotes: '...'
  return "'" + ($s -replace "'", "'\\''") + "'"
}

function Wait-HttpOkWsl([string]$url) {
  $deadline = (Get-Date).AddSeconds($HttpWaitSeconds)
  while ((Get-Date) -lt $deadline) {
    $q = Escape-BashSingleQuoted $url
    $r = Invoke-WslStdout "curl -fsS -m 2 -o /dev/null $q"
    if ($r.ExitCode -eq 0) { return }
    Start-Sleep -Seconds 2
  }
  throw "Timed out waiting for HTTP OK from WSL: $url (${HttpWaitSeconds}s)."
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw "wsl.exe not found. Install WSL or use scripts/run_bench_windows.ps1 with ab.exe on Windows PATH."
}

$abProbe = (Invoke-WslStdout "command -v ab || true").Text.Trim()
if (-not $abProbe) {
  throw "ApacheBench (ab) not found inside WSL. Install with: wsl sudo apt-get update && sudo apt-get install -y apache2-utils"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot
$pythonExe = Get-RepoPythonExe $repoRoot.Path

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

$benchBase = Resolve-BaseUrlForWsl $BaseUrl

# Probe one representative URL before starting long runs.
Wait-HttpOk ($BaseUrl.TrimEnd("/") + $paths[0])
Wait-HttpOkWsl ($benchBase + $paths[0])

$runId = "$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss'))Z_${Profile}_${Scenario}"
$outDir = Join-Path "experiments/results" $runId
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

@"
run_id=$runId
profile=$Profile
base_url=$BaseUrl
bench_base_url=$benchBase
scenario=$Scenario
concurrency=$concurrency
duration_s=$durationS
loadgen=wsl_ab
"@ | Set-Content -Encoding UTF8 (Join-Path $outDir "meta.txt")

$nRequests = $durationS * $concurrency

function Invoke-WslAbToFile([string]$url, [int]$concurrency, [int]$nRequests, [string]$outFile) {
  $q = Escape-BashSingleQuoted $url
  $bashLc = "ab -k -c $concurrency -n $nRequests $q"
  $tmpOut = [IO.Path]::GetTempFileName()
  $tmpErr = "$tmpOut.err"
  try {
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
      $p = Start-Process -FilePath "wsl.exe" -ArgumentList "bash -lc `"$bashLc`"" -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr

      $stdout = [IO.File]::ReadAllText($tmpOut)
      $stderr = ""
      if ([IO.File]::Exists($tmpErr)) { $stderr = [IO.File]::ReadAllText($tmpErr) }
      $combined = $stdout
      if ($stderr) { $combined = ($stdout + "`n" + $stderr) }

      if ($p.ExitCode -eq 0 -and ($combined -match "Requests per second:")) {
        [IO.File]::WriteAllText($outFile, $combined, (New-Object System.Text.UTF8Encoding($false)))
        return
      }

      Start-Sleep -Seconds (5 + $attempt * 5)
    }
    throw "WSL ab failed repeatedly for URL: $url"
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmpOut, $tmpErr
  }
}

for ($i = 1; $i -le $Repeat; $i++) {
  foreach ($p in $paths) {
    $url = ($benchBase + $p)
    $safePath = ($p -replace "[^a-zA-Z0-9]", "_").Trim("_")
    if (-not $safePath) { $safePath = "root" }
    $outFile = Join-Path $outDir "ab_${safePath}_rep${i}.txt"
    Write-Host "Running WSL ab: $url (c=$concurrency, n=$nRequests) -> $outFile"
    Invoke-WslAbToFile -url $url -concurrency $concurrency -nRequests $nRequests -outFile $outFile
  }
}

Write-Host "Saved results to $outDir"
