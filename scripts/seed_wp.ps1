$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$wpContainer = (docker compose ps -q wordpress)
if (-not $wpContainer) {
  throw "wordpress container not running. Start it first (scripts\\up_profile.ps1)."
}

Write-Host "Seeding WordPress content inside container..."

# Install wp-cli as root (needs /usr/local/bin write)
$installWpCli = "set -euo pipefail; if ! command -v wp >/dev/null 2>&1; then curl -sSLo /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; php /tmp/wp-cli.phar --info >/dev/null; install -m 0755 /tmp/wp-cli.phar /usr/local/bin/wp; fi"
docker exec -u root $wpContainer bash -lc $installWpCli

# Seed posts as www-data by copying a script into container (avoids Windows quoting/newline issues)
$seedScript = @'
#!/usr/bin/env bash
set -euo pipefail
cd /var/www/html

if [[ ! -f wp-config.php ]]; then
  echo "WordPress not initialized yet. Open http://localhost/ and finish setup."
  exit 2
fi

wp rewrite structure "/%postname%/" --hard || true
wp rewrite flush --hard || true

for i in 1 2 3 4 5; do
  TITLE="CS4296 Seed Post $i"
  if ! wp post list --post_type=post --field=post_title | grep -qx "$TITLE"; then
    wp post create --post_type=post --post_status=publish --post_title="$TITLE" --post_content="Seed content $i."
  fi
done

echo "Seeding complete."
wp post list --post_type=post --format=table | sed -n '1,12p'
'@

$seedScript = $seedScript -replace "`r",""
$tmp = New-TemporaryFile
# Write as UTF-8 without BOM to avoid "/usr/bin/env: No such file" on Linux.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tmp.FullName, $seedScript, $utf8NoBom)

docker cp $tmp.FullName "$wpContainer`:/tmp/seed_wp.sh" | Out-Null
Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue

docker exec -u root $wpContainer bash -lc "chmod +x /tmp/seed_wp.sh"
docker exec -u www-data $wpContainer bash -lc "/tmp/seed_wp.sh"

