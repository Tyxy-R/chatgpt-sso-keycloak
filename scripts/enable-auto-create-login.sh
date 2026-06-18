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

FLOW_ALIAS=browser-auto-create
FORMS_ALIAS="${FLOW_ALIAS} forms"
PROVIDER_ID=auto-create-username-password-form

compose() {
  docker compose "$@"
}

kc_config="/tmp/kcadm-enable-auto-create-$$.config"

cleanup() {
  compose exec -T -u root keycloak rm -f "$kc_config" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kc() {
  compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@" --config "$kc_config"
}

wait_for_keycloak() {
  local local_url="${KEYCLOAK_LOCAL_URL:-http://127.0.0.1:8080}"

  for _ in $(seq 1 120); do
    if curl -fsS "${local_url}/realms/master" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  compose logs --tail=160 keycloak >&2
  echo "Keycloak did not become ready." >&2
  return 1
}

execution_id_for_provider() {
  local flow_alias="$1"
  local provider_id="$2"

  kc get "authentication/flows/${flow_alias}/executions" -r "$KEYCLOAK_REALM" |
    jq -r --arg provider_id "$provider_id" '.[] | select(.providerId == $provider_id) | .id' |
    head -n 1
}

execution_id_for_display() {
  local flow_alias="$1"
  local display_name="$2"

  kc get "authentication/flows/${flow_alias}/executions" -r "$KEYCLOAK_REALM" |
    jq -r --arg display_name "$display_name" '.[] | select(.displayName == $display_name) | .id' |
    head -n 1
}

compose up -d postgres keycloak >/dev/null
wait_for_keycloak

compose exec -T -u root keycloak sh -c "rm -f '$kc_config' && touch '$kc_config' && chown keycloak:root '$kc_config' && chmod 600 '$kc_config'"

kc config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

if ! kc get authentication/authenticator-providers -r "$KEYCLOAK_REALM" |
  jq -e --arg id "$PROVIDER_ID" '.[] | select(.id == $id)' >/dev/null; then
  echo "Provider ${PROVIDER_ID} is not installed. Run ./scripts/build-provider.sh and restart Keycloak." >&2
  exit 1
fi

if ! kc get authentication/flows -r "$KEYCLOAK_REALM" |
  jq -e --arg alias "$FLOW_ALIAS" '.[] | select(.alias == $alias)' >/dev/null; then
  kc create authentication/flows/browser/copy -r "$KEYCLOAK_REALM" -s "newName=${FLOW_ALIAS}" >/dev/null
fi

old_execution_id="$(execution_id_for_provider "$FLOW_ALIAS" auth-username-password-form)"
if [[ -n "$old_execution_id" ]]; then
  kc delete "authentication/executions/${old_execution_id}" -r "$KEYCLOAK_REALM"
fi

auto_execution_id="$(execution_id_for_provider "$FLOW_ALIAS" "$PROVIDER_ID")"
if [[ -z "$auto_execution_id" ]]; then
  kc create "authentication/flows/${FORMS_ALIAS// /%20}/executions/execution" \
    -r "$KEYCLOAK_REALM" \
    -s "provider=${PROVIDER_ID}" >/dev/null
  auto_execution_id="$(execution_id_for_provider "$FLOW_ALIAS" "$PROVIDER_ID")"
fi

if [[ -z "$auto_execution_id" ]]; then
  echo "Could not create ${PROVIDER_ID} execution." >&2
  exit 1
fi

while true; do
  auto_index="$(
    kc get "authentication/flows/${FLOW_ALIAS}/executions" -r "$KEYCLOAK_REALM" |
      jq -r --arg id "$auto_execution_id" '.[] | select(.id == $id) | .index'
  )"
  two_fa_index="$(
    kc get "authentication/flows/${FLOW_ALIAS}/executions" -r "$KEYCLOAK_REALM" |
      jq -r '.[] | select(.displayName | contains("Browser - Conditional 2FA")) | .index' |
      head -n 1
  )"

  if [[ -z "$two_fa_index" || "$auto_index" -lt "$two_fa_index" ]]; then
    break
  fi

  kc create "authentication/executions/${auto_execution_id}/raise-priority" -r "$KEYCLOAK_REALM" >/dev/null
done

kc update "realms/${KEYCLOAK_REALM}" -s "browserFlow=${FLOW_ALIAS}"

echo "Enabled ${PROVIDER_ID} in browser flow ${FLOW_ALIAS} for realm ${KEYCLOAK_REALM}."
