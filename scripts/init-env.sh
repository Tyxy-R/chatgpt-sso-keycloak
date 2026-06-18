#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  echo ".env already exists; leaving it unchanged."
  exit 0
fi

random_secret() {
  openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_' | tr -d '='
}

umask 077
{
  echo "KEYCLOAK_HOSTNAME=sso.example.com"
  echo "KEYCLOAK_PUBLIC_URL=https://sso.example.com"
  echo "KEYCLOAK_LOCAL_URL=http://127.0.0.1:18081"
  echo "KEYCLOAK_REALM=chatgpt"
  echo "KEYCLOAK_ADMIN_USERNAME=admin"
  echo "KEYCLOAK_ADMIN_PASSWORD=$(random_secret)"
  echo "POSTGRES_PASSWORD=$(random_secret)"
  echo "ACME_EMAIL=admin@example.com"
  echo "OPENAI_SP_METADATA_URL=https://external.auth.openai.com/sso/saml/<openai-sp-entity-id>/metadata.xml"
  echo "OPENAI_SP_ENTITY_ID=<openai-sp-entity-id>"
  echo "OPENAI_ACS_URL=https://external.auth.openai.com/sso/saml/acs/<openai-sp-entity-id>"
  echo "ALLOWED_EMAIL_DOMAIN=example.com"
  echo "ALLOWED_EMAIL_DOMAINS=example.com"
} > .env

echo "Created .env with generated local credentials."
