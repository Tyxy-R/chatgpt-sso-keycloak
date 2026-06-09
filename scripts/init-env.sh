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
  echo "KEYCLOAK_HOSTNAME=sso.oaichatgpt.xyz"
  echo "KEYCLOAK_PUBLIC_URL=https://sso.oaichatgpt.xyz"
  echo "KEYCLOAK_REALM=chatgpt"
  echo "KEYCLOAK_ADMIN_USERNAME=admin"
  echo "KEYCLOAK_ADMIN_PASSWORD=$(random_secret)"
  echo "POSTGRES_PASSWORD=$(random_secret)"
  echo "ACME_EMAIL=admin@oaichatgpt.xyz"
  echo "OPENAI_SP_METADATA_URL=https://external.auth.openai.com/sso/saml/ATZB94xJKf9FsbARIruJxTv5f/metadata.xml"
  echo "OPENAI_SP_ENTITY_ID=ATZB94xJKf9FsbARIruJxTv5f"
  echo "OPENAI_ACS_URL=https://external.auth.openai.com/sso/saml/acs/ATZB94xJKf9FsbARIruJxTv5f"
  echo "ALLOWED_EMAIL_DOMAIN=oaichatgpt.xyz"
} > .env

echo "Created .env with generated local credentials."
