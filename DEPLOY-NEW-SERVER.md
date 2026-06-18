# Deploy on a New Server

## DNS

Point your public IdP hostname to the server before testing:

```text
Type: A or CNAME
Name: sso
Value: <new-server-ip-or-target>
```

Wait until DNS resolves:

```bash
dig @1.1.1.1 +short sso.example.com A
```

## Fresh Deployment

```bash
cd /root/chatgpt-sso-keycloak
cp .env.example .env
chmod 600 .env
```

Edit `.env` and set:

```text
KEYCLOAK_HOSTNAME
KEYCLOAK_PUBLIC_URL
ACME_EMAIL
OPENAI_SP_ENTITY_ID
OPENAI_ACS_URL
OPENAI_SP_METADATA_URL
ALLOWED_EMAIL_DOMAIN
ALLOWED_EMAIL_DOMAINS
AUTO_CREATE_USER_PASSWORD
```

Start the core services:

```bash
docker compose up -d postgres keycloak
./scripts/configure-openai-saml.sh
./scripts/enable-auto-create-login.sh
./scripts/check.sh
```

If the bundled Caddy service owns HTTPS on this host:

```bash
docker compose --profile caddy up -d
```

If another reverse proxy owns 80/443, proxy your public hostname to:

```text
http://127.0.0.1:18081
```

## OpenAI Side

Use this IdP metadata URL in OpenAI SSO setup:

```text
https://<KEYCLOAK_HOSTNAME>/realms/<KEYCLOAK_REALM>/protocol/saml/descriptor
```

If you add another ChatGPT workspace, run `configure-openai-saml.sh` with that
workspace's SP entity ID and ACS URL. Existing SAML clients are preserved.

## Migration Notes

The database volume contains Keycloak realms, users, keys, and sessions. Moving
only the repository files does not migrate existing Keycloak state. Back up and
restore the Docker volume or database if you need to keep users and signing keys.

If the public hostname changes, update `.env`, DNS, and the IdP metadata URL in
OpenAI. OpenAI may cache IdP metadata briefly.
