#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./scripts/quick-deploy.sh [options]

Options:
  --host HOST                 Public Keycloak host, for example sso.example.com
  --email-domains DOMAINS     Allowed email domains, comma-separated
  --openai-id ID              OpenAI service provider entity ID from SAML Step 2
  --auto-password PASSWORD    Shared initial password for auto-created users
  --acme-email EMAIL          Email for Caddy/Let's Encrypt
  --caddy                     Start the bundled Caddy HTTPS reverse proxy
  --no-auto-create            Do not enable auto-create login flow
  --force                     Replace an existing .env
  -h, --help                  Show this help

Interactive mode:
  Run ./scripts/quick-deploy.sh and answer the prompts.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required."
}

random_secret() {
  openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_' | tr -d '='
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_csv() {
  local raw="$1"
  local item out

  out=""
  IFS=',' read -ra items <<< "$raw"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    if [[ -n "$item" ]]; then
      if [[ -n "$out" ]]; then
        out+=","
      fi
      out+="$item"
    fi
  done

  printf '%s' "$out"
}

first_csv_value() {
  local raw="$1"
  local first
  IFS=',' read -r first _ <<< "$raw"
  trim "$first"
}

validate_no_placeholder() {
  local name="$1"
  local value="$2"

  [[ -n "$value" ]] || die "$name is required."
  [[ "$value" != *"<"* && "$value" != *">"* ]] || die "$name still contains a placeholder."
}

validate_simple_env_value() {
  local name="$1"
  local value="$2"

  [[ "$value" != *$'\n'* ]] || die "$name cannot contain newlines."
  [[ "$value" != *[[:space:]]* ]] || die "$name cannot contain spaces."
}

prompt_required() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name:-}"

  if [[ -n "$current" ]]; then
    return 0
  fi

  read -rp "$prompt: " current
  printf -v "$var_name" '%s' "$current"
}

prompt_password() {
  if [[ -n "$auto_password" || "$auto_create" == "false" ]]; then
    return 0
  fi

  local password confirm
  read -rsp "Shared initial password for auto-created users: " password
  echo
  read -rsp "Confirm password: " confirm
  echo

  [[ -n "$password" ]] || die "password cannot be empty."
  [[ "$password" == "$confirm" ]] || die "passwords do not match."
  auto_password="$password"
}

write_env() {
  local first_domain
  local env_tmp

  first_domain="$(first_csv_value "$email_domains")"
  env_tmp="$(mktemp)"

  umask 077
  {
    printf 'KEYCLOAK_HOSTNAME=%s\n' "$host"
    printf 'KEYCLOAK_PUBLIC_URL=https://%s\n' "$host"
    printf 'KEYCLOAK_LOCAL_URL=http://127.0.0.1:18081\n'
    printf 'KEYCLOAK_REALM=chatgpt\n'
    printf 'KEYCLOAK_ADMIN_USERNAME=admin\n'
    printf 'KEYCLOAK_ADMIN_PASSWORD=%s\n' "$(random_secret)"
    printf 'POSTGRES_PASSWORD=%s\n' "$(random_secret)"
    printf 'ACME_EMAIL=%s\n' "$acme_email"
    printf 'OPENAI_SP_METADATA_URL=https://external.auth.openai.com/sso/saml/%s/metadata.xml\n' "$openai_id"
    printf 'OPENAI_SP_ENTITY_ID=%s\n' "$openai_id"
    printf 'OPENAI_ACS_URL=https://external.auth.openai.com/sso/saml/acs/%s\n' "$openai_id"
    printf 'ALLOWED_EMAIL_DOMAIN=%s\n' "$first_domain"
    printf 'ALLOWED_EMAIL_DOMAINS=%s\n' "$email_domains"
    printf 'AUTO_CREATE_USER_PASSWORD=%s\n' "$auto_password"
  } > "$env_tmp"

  mv "$env_tmp" .env
  chmod 600 .env
}

host=""
email_domains=""
openai_id=""
auto_password=""
acme_email=""
use_caddy="false"
auto_create="true"
force="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      host="${2:-}"
      shift 2
      ;;
    --email-domains)
      email_domains="${2:-}"
      shift 2
      ;;
    --openai-id)
      openai_id="${2:-}"
      shift 2
      ;;
    --auto-password)
      auto_password="${2:-}"
      shift 2
      ;;
    --acme-email)
      acme_email="${2:-}"
      shift 2
      ;;
    --caddy)
      use_caddy="true"
      shift
      ;;
    --no-auto-create)
      auto_create="false"
      shift
      ;;
    --force)
      force="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

need_cmd docker
need_cmd openssl
need_cmd curl
docker compose version >/dev/null 2>&1 || die "docker compose is required."

if [[ -f .env && "$force" != "true" ]]; then
  die ".env already exists. Use ./scripts/add-workspace.sh for existing deployments, or pass --force to replace .env."
fi

prompt_required host "Public SSO host, for example sso.example.com"
prompt_required email_domains "Allowed email domains, comma-separated, for example team.example.com"
prompt_required openai_id "OpenAI service provider entity ID from Step 2"

email_domains="$(normalize_csv "$email_domains")"

if [[ -z "$acme_email" ]]; then
  read -rp "Email for HTTPS certificates, for example admin@example.com: " acme_email
fi

if [[ "$use_caddy" == "false" ]]; then
  read -rp "Start bundled Caddy for HTTPS? Type yes if this server does not already use port 80/443 [no]: " caddy_answer
  case "${caddy_answer,,}" in
    y|yes)
      use_caddy="true"
      ;;
  esac
fi

prompt_password

validate_no_placeholder "host" "$host"
validate_no_placeholder "email_domains" "$email_domains"
validate_no_placeholder "openai_id" "$openai_id"
validate_no_placeholder "acme_email" "$acme_email"
validate_simple_env_value "host" "$host"
validate_simple_env_value "openai_id" "$openai_id"
validate_simple_env_value "acme_email" "$acme_email"
if [[ "$auto_create" == "true" ]]; then
  validate_simple_env_value "auto_password" "$auto_password"
fi

if [[ "$auto_create" == "false" ]]; then
  auto_password=""
fi

write_env

if [[ "$auto_create" == "true" && ! -f providers/auto-create-username-password-form-1.0.0.jar ]]; then
  ./scripts/build-provider.sh
fi

docker compose up -d postgres keycloak

./scripts/configure-openai-saml.sh \
  "$openai_id" \
  "https://external.auth.openai.com/sso/saml/acs/${openai_id}" \
  "https://external.auth.openai.com/sso/saml/${openai_id}/metadata.xml"

if [[ "$auto_create" == "true" ]]; then
  docker compose up -d --force-recreate keycloak
  ./scripts/enable-auto-create-login.sh
fi

if [[ "$use_caddy" == "true" ]]; then
  docker compose --profile caddy up -d
fi

echo
echo "Deployment commands completed."
echo "OpenAI Step 3 metadata URL:"
echo "  https://${host}/realms/chatgpt/protocol/saml/descriptor"
echo
if [[ "$use_caddy" != "true" ]]; then
  echo "Configure your reverse proxy to:"
  echo "  http://127.0.0.1:18081"
  echo
fi
echo "Run this check after DNS and HTTPS are ready:"
echo "  ./scripts/check.sh"
