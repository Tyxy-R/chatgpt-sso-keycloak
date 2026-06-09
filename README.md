# ChatGPT Enterprise SAML IdP

This directory runs a local Keycloak identity provider for ChatGPT Enterprise SSO.

## Public URL

Use this hostname for the identity provider:

```text
sso.oaichatgpt.xyz
```

Create this DNS record before running the OpenAI SSO test:

```text
Type: A
Name: sso
Value: 198.199.75.36
```

## Start and configure

```bash
./scripts/init-env.sh
docker compose up -d
./scripts/configure-openai-saml.sh
./scripts/check.sh
```

## OpenAI SSO fields

In OpenAI Step 3, use this metadata URL:

```text
https://sso.oaichatgpt.xyz/realms/chatgpt/protocol/saml/descriptor
```

If OpenAI asks for manual metadata instead:

```text
SSO URL: https://sso.oaichatgpt.xyz/realms/chatgpt/protocol/saml
Entity ID: https://sso.oaichatgpt.xyz/realms/chatgpt
Certificate: use the certificate embedded in the Keycloak metadata XML
```

## Users

Create a realm user for each employee email:

```bash
./scripts/create-user.sh alice@oaichatgpt.xyz Alice Zhang
```

The script prompts for the user's password without printing it to the terminal.
The email domain must match the verified OpenAI domain.

Bulk-create or update users from a CSV:

```bash
./scripts/create-users-bulk.sh users.csv
```

CSV format:

```text
email,firstName,lastName
alice@oaichatgpt.xyz,Alice,Zhang
```

The bulk script prompts once for a shared initial password. Add
`--force-password-change` when users should be forced to replace that shared
initial password on first login.

## Auto-create users on login

The custom provider creates a missing `@oaichatgpt.xyz` user during the
username/password login attempt, then validates the submitted password.

```bash
./scripts/build-provider.sh
./scripts/set-auto-create-password.sh
docker compose up -d --force-recreate keycloak
./scripts/enable-auto-create-login.sh
```

The password is stored in `.env` as `AUTO_CREATE_USER_PASSWORD` and is not
hard-coded into the provider jar.

## Keycloak admin

Admin console:

```text
https://sso.oaichatgpt.xyz/admin/
```

Local admin console before DNS is ready:

```text
http://127.0.0.1:8080/admin/
```

The admin username and generated password are stored in `.env`.
