$ErrorActionPreference = "Stop"

Write-Host "Installing ApacheBench (ab) inside WSL Ubuntu..."

# Ensure WSL is available
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw "wsl.exe not found."
}

# Install apache2-utils which contains ab
wsl bash -lc "sudo apt-get update -y && sudo apt-get install -y apache2-utils"
wsl bash -lc "ab -V"

Write-Host "WSL ab installed."

