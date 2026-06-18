#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  ./scripts/init-env.sh
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

if [[ $# -gt 3 ]]; then
  echo "Usage: $0 [openai-sp-entity-id openai-acs-url [openai-sp-metadata-url]]" >&2
  exit 2
fi

if [[ $# -ge 1 ]]; then
  OPENAI_SP_ENTITY_ID="$1"
fi

if [[ $# -ge 2 ]]; then
  OPENAI_ACS_URL="$2"
fi

if [[ $# -ge 3 ]]; then
  OPENAI_SP_METADATA_URL="$3"
elif [[ $# -ge 1 ]]; then
  OPENAI_SP_METADATA_URL="https://external.auth.openai.com/sso/saml/${OPENAI_SP_ENTITY_ID}/metadata.xml"
fi

compose() {
  docker compose "$@"
}

kc() {
  compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

wait_for_keycloak() {
  local local_url="${KEYCLOAK_LOCAL_URL:-http://127.0.0.1:8080}"

  for _ in $(seq 1 120); do
    if curl -fsS "${local_url}/realms/master" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Keycloak did not become ready on ${local_url}." >&2
  compose logs --tail=120 keycloak >&2
  return 1
}

client_json="$(mktemp)"
trap 'rm -f "$client_json"' EXIT

compose up -d postgres keycloak
wait_for_keycloak

kc config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

if ! kc get "realms/${KEYCLOAK_REALM}" >/dev/null 2>&1; then
  kc create realms \
    -s "realm=${KEYCLOAK_REALM}" \
    -s enabled=true \
    -s "displayName=ChatGPT SSO" \
    -s registrationAllowed=false \
    -s resetPasswordAllowed=true \
    -s rememberMe=true \
    -s loginWithEmailAllowed=true \
    -s duplicateEmailsAllowed=false >/dev/null
fi

cat > "$client_json" <<JSON
{
  "clientId": "${OPENAI_SP_ENTITY_ID}",
  "name": "OpenAI ChatGPT Enterprise",
  "description": "SAML service provider for ChatGPT Enterprise.",
  "enabled": true,
  "protocol": "saml",
  "publicClient": false,
  "frontchannelLogout": false,
  "redirectUris": [
    "${OPENAI_ACS_URL}"
  ],
  "baseUrl": "https://chatgpt.com",
  "attributes": {
    "saml.assertion.signature": "true",
    "saml.server.signature": "true",
    "saml.server.signature.keyinfo.ext": "false",
    "saml.signature.algorithm": "RSA_SHA256",
    "saml_signature_canonicalization_method": "http://www.w3.org/2001/10/xml-exc-c14n#",
    "saml_force_name_id_format": "true",
    "saml_name_id_format": "email",
    "saml.client.signature": "false",
    "saml.encrypt": "false",
    "saml.authnstatement": "true",
    "saml.force.post.binding": "true",
    "saml.onetimeuse.condition": "false",
    "saml_assertion_consumer_url_post": "${OPENAI_ACS_URL}"
  },
  "protocolMappers": [
    {
      "name": "id",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "user.attribute": "email",
        "attribute.name": "id",
        "attribute.nameformat": "Basic",
        "friendly.name": "id"
      }
    },
    {
      "name": "email",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "user.attribute": "email",
        "attribute.name": "email",
        "attribute.nameformat": "Basic",
        "friendly.name": "email"
      }
    },
    {
      "name": "Email Address",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "user.attribute": "email",
        "attribute.name": "Email Address",
        "attribute.nameformat": "Basic",
        "friendly.name": "Email Address"
      }
    },
    {
      "name": "firstName",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "user.attribute": "firstName",
        "attribute.name": "firstName",
        "attribute.nameformat": "Basic",
        "friendly.name": "firstName"
      }
    },
    {
      "name": "First Name",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "user.attribute": "firstName",
        "attribute.name": "First Name",
        "attribute.nameformat": "Basic",
        "friendly.name": "First Name"
      }
    },
    {
      "name": "lastName",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "user.attribute": "lastName",
        "attribute.name": "lastName",
        "attribute.nameformat": "Basic",
        "friendly.name": "lastName"
      }
    },
    {
      "name": "Last Name",
      "protocol": "saml",
      "protocolMapper": "saml-user-property-mapper",
      "consentRequired": false,
      "config": {
        "user.attribute": "lastName",
        "attribute.name": "Last Name",
        "attribute.nameformat": "Basic",
        "friendly.name": "Last Name"
      }
    }
  ]
}
JSON

compose cp "$client_json" keycloak:/tmp/openai-saml-client.json >/dev/null
compose exec -T -u root keycloak chmod 0644 /tmp/openai-saml-client.json
client_id="$(
  kc get clients -r "$KEYCLOAK_REALM" --fields id,clientId |
    jq -r --arg client_id "$OPENAI_SP_ENTITY_ID" \
      '.[] | select(.clientId == $client_id) | .id' |
    head -n 1
)"

if [[ -n "$client_id" ]]; then
  kc update "clients/${client_id}" -r "$KEYCLOAK_REALM" -f /tmp/openai-saml-client.json >/dev/null
else
  kc create clients -r "$KEYCLOAK_REALM" -f /tmp/openai-saml-client.json >/dev/null
fi

echo "Configured OpenAI SAML client in realm ${KEYCLOAK_REALM}."
echo "Identity Provider metadata URL: ${KEYCLOAK_PUBLIC_URL}/realms/${KEYCLOAK_REALM}/protocol/saml/descriptor"
