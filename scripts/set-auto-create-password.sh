#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo ".env is missing. Run ./scripts/init-env.sh first." >&2
  exit 1
fi

if [[ ! -t 0 ]]; then
  echo "Password must be entered from an interactive terminal." >&2
  exit 1
fi

read -rsp "Auto-create initial password: " password
echo
read -rsp "Confirm auto-create initial password: " password_confirm
echo

if [[ -z "$password" ]]; then
  echo "Password cannot be empty." >&2
  exit 1
fi

if [[ "$password" != "$password_confirm" ]]; then
  echo "Passwords do not match." >&2
  exit 1
fi

tmp_env="$(mktemp)"
trap 'rm -f "$tmp_env"' EXIT

if grep -q '^AUTO_CREATE_USER_PASSWORD=' .env; then
  sed 's/^AUTO_CREATE_USER_PASSWORD=.*/AUTO_CREATE_USER_PASSWORD=/' .env > "$tmp_env"
else
  cp .env "$tmp_env"
  printf '\nAUTO_CREATE_USER_PASSWORD=\n' >> "$tmp_env"
fi

awk -v password="$password" '
  /^AUTO_CREATE_USER_PASSWORD=/ {
    print "AUTO_CREATE_USER_PASSWORD=" password
    next
  }
  { print }
' "$tmp_env" > "${tmp_env}.new"
mv "${tmp_env}.new" "$tmp_env"

chmod 0600 "$tmp_env"
mv "$tmp_env" .env
trap - EXIT

echo "Configured AUTO_CREATE_USER_PASSWORD in .env."
