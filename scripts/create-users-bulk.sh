#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat >&2 <<'USAGE'
Usage: ./scripts/create-users-bulk.sh [--force-password-change] users.csv

CSV format:
  email,firstName,lastName
  alice@example.com,Alice,Zhang

Blank lines and lines starting with # are ignored. The header row is optional.
USAGE
}

force_password_change=false
users_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-password-change)
      force_password_change=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "$users_file" ]]; then
        echo "Only one users file can be provided." >&2
        usage
        exit 2
      fi
      users_file="$1"
      shift
      ;;
  esac
done

if [[ -z "$users_file" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$users_file" ]]; then
  echo "Users file not found: ${users_file}" >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo ".env is missing. Run ./scripts/init-env.sh first." >&2
  exit 1
fi

if [[ ! -t 0 ]]; then
  echo "Initial password must be entered from an interactive terminal." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

allowed_email_domains="${ALLOWED_EMAIL_DOMAINS:-${ALLOWED_EMAIL_DOMAIN}}"

read -rsp "Initial password for all users: " password
echo
read -rsp "Confirm initial password: " password_confirm
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
kcadm_config_container="/tmp/kcadm-bulk-users-$$.config"

cleanup() {
  rm -f "$kcadm_config"
  docker compose exec -T -u root keycloak rm -f "$kcadm_config_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

compose() {
  docker compose "$@"
}

kc() {
  compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@" --config "$kcadm_config_container"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_allowed_email() {
  local value="$1"
  local domain

  IFS=',' read -ra domains <<< "$allowed_email_domains"
  for domain in "${domains[@]}"; do
    domain="$(trim "$domain")"
    if [[ -n "$domain" && "$value" == *@${domain} ]]; then
      return 0
    fi
  done

  return 1
}

find_user_id() {
  local email="$1"
  local query_field="$2"

  kc get users -r "$KEYCLOAK_REALM" -q "${query_field}=${email}" --fields id --format csv |
    tail -n +2 |
    tr -d '"\r' |
    head -n 1
}

upsert_user() {
  local email="$1"
  local first_name="$2"
  local last_name="$3"
  local user_id create_output action

  user_id="$(find_user_id "$email" username)"
  if [[ -z "$user_id" ]]; then
    user_id="$(find_user_id "$email" email)"
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
    action="created"

    if [[ -z "$user_id" ]]; then
      user_id="$(find_user_id "$email" username)"
    fi
  else
    kc update "users/${user_id}" -r "$KEYCLOAK_REALM" \
      -s "username=${email}" \
      -s "email=${email}" \
      -s "firstName=${first_name}" \
      -s "lastName=${last_name}" \
      -s emailVerified=true \
      -s enabled=true >/dev/null
    action="updated"
  fi

  if [[ -z "$user_id" ]]; then
    echo "failed ${email}: could not resolve user id" >&2
    return 1
  fi

  kc set-password -r "$KEYCLOAK_REALM" --userid "$user_id" --new-password "$password" >/dev/null

  if [[ "$force_password_change" == true ]]; then
    kc update "users/${user_id}" -r "$KEYCLOAK_REALM" -s 'requiredActions=["UPDATE_PASSWORD"]' >/dev/null
  fi

  echo "${action} ${email}"
}

compose cp "$kcadm_config" "keycloak:${kcadm_config_container}" >/dev/null
compose exec -T -u root keycloak chown keycloak:root "$kcadm_config_container"
compose exec -T -u root keycloak chmod 0600 "$kcadm_config_container"

kc config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USERNAME" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

total=0
ok=0
failed=0
line_no=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line_no=$((line_no + 1))
  raw_line="${raw_line%$'\r'}"

  if [[ -z "${raw_line//[[:space:]]/}" || "$raw_line" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  IFS=',' read -r email first_name last_name _ <<< "$raw_line"
  email="$(trim "${email:-}")"
  first_name="$(trim "${first_name:-}")"
  last_name="$(trim "${last_name:-}")"

  if [[ "${email,,}" == "email" ]]; then
    continue
  fi

  total=$((total + 1))

  if ! is_allowed_email "$email"; then
    echo "failed line ${line_no}: ${email} is outside allowed domains: ${allowed_email_domains}" >&2
    failed=$((failed + 1))
    continue
  fi

  if [[ -z "$first_name" ]]; then
    first_name="${email%@*}"
  fi

  if [[ -z "$last_name" ]]; then
    last_name="User"
  fi

  if upsert_user "$email" "$first_name" "$last_name"; then
    ok=$((ok + 1))
  else
    failed=$((failed + 1))
  fi
done < "$users_file"

echo "Done. processed=${total} ok=${ok} failed=${failed}"

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
