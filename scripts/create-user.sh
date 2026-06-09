#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 email [first-name] [last-name]" >&2
  exit 2
fi

if [[ ! -f .env ]]; then
  echo ".env is missing. Run ./scripts/init-env.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

email="$1"
first_name="${2:-User}"
last_name="${3:-Account}"

if [[ "$email" != *@${ALLOWED_EMAIL_DOMAIN} ]]; then
  echo "Email must be under @${ALLOWED_EMAIL_DOMAIN} for the verified OpenAI domain." >&2
  exit 1
fi

if [[ ! -t 0 ]]; then
  echo "Password must be entered from an interactive terminal." >&2
  exit 1
fi

read -rsp "Password for ${email}: " password
echo
read -rsp "Confirm password: " password_confirm
echo

if [[ -z "$password" ]]; then
  echo "Password cannot be empty." >&2
  exit 1
fi

if [[ "$password" != "$password_confirm" ]]; then
  echo "Passwords do not match." >&2
  exit 1
fi

kcadm_config="$(mktemp)"
trap 'rm -f "$kcadm_config"' EXIT

compose() {
  docker compose "$@"
}

kc() {
  compose exec -T \
    keycloak /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm-create-user.config
}

compose cp "$kcadm_config" keycloak:/tmp/kcadm-create-user.config >/dev/null
compose exec -T -u root keycloak chown keycloak:root /tmp/kcadm-create-user.config
compose exec -T -u root keycloak chmod 0600 /tmp/kcadm-create-user.config

kc config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

find_user_id() {
  local query_field="$1"

  kc get users -r "$KEYCLOAK_REALM" -q "${query_field}=${email}" --fields id --format csv |
    tail -n +2 |
    tr -d '"\r' |
    head -n 1
}

user_id="$(find_user_id username)"
if [[ -z "$user_id" ]]; then
  user_id="$(find_user_id email)"
fi

if [[ -z "$user_id" ]]; then
  create_output="$(
    kc create users -r "$KEYCLOAK_REALM" \
    -s "username=${email}" \
    -s "email=${email}" \
    -s "firstName=${first_name}" \
    -s "lastName=${last_name}" \
    -s emailVerified=true \
      -s enabled=true
  )"
  user_id="$(printf '%s\n' "$create_output" | sed -n "s/^Created new user with id '\\([^']*\\)'.*/\\1/p")"

  if [[ -z "$user_id" ]]; then
    user_id="$(find_user_id username)"
  fi
else
  kc update "users/${user_id}" -r "$KEYCLOAK_REALM" \
    -s "username=${email}" \
    -s "email=${email}" \
    -s "firstName=${first_name}" \
    -s "lastName=${last_name}" \
    -s emailVerified=true \
    -s enabled=true >/dev/null
fi

if [[ -z "$user_id" ]]; then
  echo "Could not resolve created user id for ${email}." >&2
  exit 1
fi

kc set-password -r "$KEYCLOAK_REALM" --userid "$user_id" --new-password "$password" >/dev/null

echo "User ready: ${email}"
