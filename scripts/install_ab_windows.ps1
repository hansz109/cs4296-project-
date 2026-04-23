$ErrorActionPreference = "Stop"

Write-Host "Installing ApacheBench (ab) on Windows..."

if (Get-Command ab.exe -ErrorAction SilentlyContinue) {
  ab.exe -V
  exit 0
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
  # Apache httpd package includes ab.exe.
  Write-Host "Trying winget..."
  winget install -e --id Apache.ApacheHTTPServer --source winget
} elseif (Get-Command choco -ErrorAction SilentlyContinue) {
  choco install -y apache-httpd
} else {
  Write-Host "Neither winget nor Chocolatey found."
  Write-Host "Please manually install Apache httpd (includes ab.exe), then ensure ab.exe is on PATH."
  Write-Host "Fallback: install ab inside WSL with scripts\\install_ab_wsl.ps1"
  exit 2
}

if (-not (Get-Command ab.exe -ErrorAction SilentlyContinue)) {
  Write-Host "ab.exe not found on PATH after install."
  Write-Host "You may need to restart your terminal, or add Apache bin directory to PATH."
  Write-Host "Fallback: install ab inside WSL with scripts\\install_ab_wsl.ps1"
  exit 3
}

ab.exe -V

