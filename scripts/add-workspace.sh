#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./scripts/add-workspace.sh <openai-sp-entity-id> [email-domain-or-domains]

Examples:
  ./scripts/add-workspace.sh abc123
  ./scripts/add-workspace.sh abc123 team.example.com
  ./scripts/add-workspace.sh abc123 team1.example.com,team2.example.com

The script derives the OpenAI ACS URL and metadata URL from the entity ID.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
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

csv_contains() {
  local csv="$1"
  local needle="$2"
  local item

  IFS=',' read -ra items <<< "$csv"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

merge_csv() {
  local existing="$1"
  local added="$2"
  local item merged

  merged="$(normalize_csv "$existing")"
  added="$(normalize_csv "$added")"

  IFS=',' read -ra items <<< "$added"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    if [[ -n "$item" ]] && ! csv_contains "$merged" "$item"; then
      if [[ -n "$merged" ]]; then
        merged+=","
      fi
      merged+="$item"
    fi
  done

  printf '%s' "$merged"
}

first_csv_value() {
  local raw="$1"
  local first
  IFS=',' read -r first _ <<< "$raw"
  trim "$first"
}

set_env_var() {
  local key="$1"
  local value="$2"
  local tmp

  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' .env > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" .env
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ -f .env ]] || die ".env is missing. Run ./scripts/quick-deploy.sh first."

openai_id="$1"
new_domains="${2:-}"

[[ -n "$openai_id" ]] || die "OpenAI service provider entity ID is required."
[[ "$openai_id" != *"<"* && "$openai_id" != *">"* ]] || die "OpenAI entity ID still contains a placeholder."

./scripts/configure-openai-saml.sh \
  "$openai_id" \
  "https://external.auth.openai.com/sso/saml/acs/${openai_id}" \
  "https://external.auth.openai.com/sso/saml/${openai_id}/metadata.xml"

if [[ -n "$new_domains" ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a

  current_domains="${ALLOWED_EMAIL_DOMAINS:-${ALLOWED_EMAIL_DOMAIN:-}}"
  merged_domains="$(merge_csv "$current_domains" "$new_domains")"

  if [[ "$merged_domains" != "$(normalize_csv "$current_domains")" ]]; then
    set_env_var ALLOWED_EMAIL_DOMAINS "$merged_domains"
    if [[ -z "${ALLOWED_EMAIL_DOMAIN:-}" ]]; then
      set_env_var ALLOWED_EMAIL_DOMAIN "$(first_csv_value "$merged_domains")"
    fi
    docker compose up -d --force-recreate keycloak
    echo "Allowed email domains updated: ${merged_domains}"
  else
    echo "Allowed email domains unchanged: ${merged_domains}"
  fi
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

echo
echo "Workspace configured."
echo "OpenAI Step 3 metadata URL:"
echo "  ${KEYCLOAK_PUBLIC_URL}/realms/${KEYCLOAK_REALM}/protocol/saml/descriptor"
