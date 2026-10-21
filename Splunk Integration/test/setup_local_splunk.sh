#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$HERE/../resilio_reporting"
NAME="${SPLUNK_CONTAINER:-splunk-test}"
BASE_URL="${BASE_URL:-http://host.docker.internal:8446}"
API_TOKEN="${API_TOKEN:-test-token}"
SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-password}"

if ! docker inspect "$NAME" >/dev/null 2>&1; then
  docker run -d --name "$NAME" -p 8000:8000 -p 18088:8088 -p 8089:8089 \
    -e SPLUNK_START_ARGS=--accept-license -e SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com \
    -e SPLUNK_PASSWORD="$SPLUNK_PASSWORD" splunk/splunk:latest
else
  docker start "$NAME" >/dev/null
fi

echo "Waiting for Splunk to become healthy..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$NAME")" = "healthy" ]; do sleep 5; done

docker exec -u root "$NAME" rm -rf /opt/splunk/etc/apps/resilio_reporting
docker cp "$APP_SRC" "$NAME":/opt/splunk/etc/apps/resilio_reporting

LOCAL_CONF="$(mktemp)"
cat > "$LOCAL_CONF" <<CONF
[resilio_reporting://local]
base_url = $BASE_URL
api_token = $API_TOKEN
interval = 60
tls_verify = false
CONF
docker exec -u root "$NAME" mkdir -p /opt/splunk/etc/apps/resilio_reporting/local
docker cp "$LOCAL_CONF" "$NAME":/opt/splunk/etc/apps/resilio_reporting/local/inputs.conf
rm -f "$LOCAL_CONF"
docker exec -u root "$NAME" chown -R splunk:splunk /opt/splunk/etc/apps/resilio_reporting

docker exec -u splunk "$NAME" /opt/splunk/bin/splunk restart
echo "Done. UI: http://localhost:8000 (admin / $SPLUNK_PASSWORD). Search: index=resilio"
