#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo ".env is missing. Run ./scripts/init-env.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

echo "Local Keycloak:"
curl -fsS "http://127.0.0.1:8080/realms/${KEYCLOAK_REALM}" >/dev/null
echo "  ok http://127.0.0.1:8080/realms/${KEYCLOAK_REALM}"

echo "Local SAML metadata:"
curl -fsS "http://127.0.0.1:8080/realms/${KEYCLOAK_REALM}/protocol/saml/descriptor" >/dev/null
echo "  ok http://127.0.0.1:8080/realms/${KEYCLOAK_REALM}/protocol/saml/descriptor"

echo "Public DNS:"
public_ip="$(curl -4 -fsS https://ifconfig.me || true)"
dns_ip="$(dig @1.1.1.1 +short "${KEYCLOAK_HOSTNAME}" A | tail -n 1 || true)"
echo "  server public IPv4: ${public_ip:-unknown}"
echo "  ${KEYCLOAK_HOSTNAME} A record: ${dns_ip:-missing}"

if [[ -n "$public_ip" && "$dns_ip" == "$public_ip" ]]; then
  echo "  dns ok"
else
  echo "  dns not ready; create A record ${KEYCLOAK_HOSTNAME} -> ${public_ip:-server-ip}"
fi

echo "OpenAI Step 3 metadata URL:"
echo "  ${KEYCLOAK_PUBLIC_URL}/realms/${KEYCLOAK_REALM}/protocol/saml/descriptor"
