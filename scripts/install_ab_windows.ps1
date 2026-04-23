$ErrorActionPreference = "Stop"

Write-Host "Installing ApacheBench (ab) on Windows..."

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
  Write-Host "Chocolatey not found."
  Write-Host "Option A (recommended): Install Chocolatey, then re-run this script."
  Write-Host "Option B: Manually install Apache httpd (includes ab.exe), then ensure ab.exe is on PATH."
  exit 2
}

# Apache HTTP Server package includes ab.exe.
choco install -y apache-httpd

if (-not (Get-Command ab.exe -ErrorAction SilentlyContinue)) {
  Write-Host "ab.exe not found on PATH after install."
  Write-Host "You may need to restart your terminal, or add Apache bin directory to PATH."
  exit 3
}

ab.exe -V

