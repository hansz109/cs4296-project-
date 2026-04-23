#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Minimal deterministic seeding without requiring wp-cli host install:
# - installs wp-cli inside the wordpress container (downloaded once)
# - creates a few posts with fixed titles

WP_CONTAINER="$(docker compose ps -q wordpress)"
if [[ -z "${WP_CONTAINER}" ]]; then
  echo "wordpress container not running. Start the stack first." >&2
  exit 1
fi

# Install wp-cli (needs root to write /usr/local/bin)
docker exec -u root "${WP_CONTAINER}" bash -lc '
set -euo pipefail
if ! command -v wp >/dev/null 2>&1; then
  curl -sSLo /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  php /tmp/wp-cli.phar --info >/dev/null
  install -m 0755 /tmp/wp-cli.phar /usr/local/bin/wp
fi
'

docker exec -u www-data "${WP_CONTAINER}" bash -lc '
set -euo pipefail
cd /var/www/html

if [[ ! -f wp-config.php ]]; then
  echo "WordPress not initialized via web installer yet."
  echo "Open http://localhost/ in browser and finish the initial setup first."
  exit 2
fi

wp rewrite structure "/%postname%/" --hard || true
wp rewrite flush --hard || true

for i in 1 2 3 4 5; do
  TITLE="CS4296 Seed Post ${i}"
  if ! wp post list --post_type=post --field=post_title | grep -qx "${TITLE}"; then
    wp post create --post_type=post --post_status=publish --post_title="${TITLE}" --post_content="Seed content ${i}."
  fi
done

echo "Seeding complete. Example post list:"
wp post list --post_type=post --format=table | head -n 10
'

