#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Minimal deterministic seeding without requiring wp-cli host install:
# - installs wp-cli inside the wordpress container (downloaded once)
# - creates a few posts with fixed titles

WP_CONTAINER="$(docker compose ps -q wordpress)"
if [[ -z "${WP_CONTAINER}" ]]; then
  echo "wordpress container not running. Run scripts/up.sh first." >&2
  exit 1
fi

docker exec "${WP_CONTAINER}" bash -lc '
set -euo pipefail
cd /var/www/html

if [[ ! -f wp-config.php ]]; then
  echo "WordPress not initialized via web installer yet."
  echo "Open http://<EC2_IP>/ in browser and finish the initial setup first."
  exit 2
fi

if [[ ! -f /tmp/wp-cli.phar ]]; then
  curl -sSLo /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  php /tmp/wp-cli.phar --info >/dev/null
fi

wp() {
  runuser -u www-data -- php /tmp/wp-cli.phar "$@"
}

# Ensure pretty permalinks are enabled (optional, but stabilizes routing)
wp rewrite structure "/%postname%/" --hard || true
wp rewrite flush --hard || true

for i in 1 2 3 4 5; do
  TITLE="CS4296 Seed Post ${i}"
  if ! wp post list --post_type=post --field=post_title | grep -qx "${TITLE}"; then
    wp post create --post_type=post --post_status=publish --post_title="${TITLE}" --post_content="Seed content ${i}."
  fi
done

echo "Seeding complete. Example post id:"
wp post list --post_type=post --format=table | head -n 10
'

