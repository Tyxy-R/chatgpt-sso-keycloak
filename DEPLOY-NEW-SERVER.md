# Deploy on a New Server

## DNS

Point the SSO hostname to the new server IP before testing:

```text
Type: A
Name: sso
Value: <new-server-ip>
```

Wait until:

```bash
dig @1.1.1.1 +short sso.oaichatgpt.xyz A
```

returns the new server IP.

## Fresh deployment

Use this path on the new server:

```bash
cd /root/chatgpt-sso-keycloak
./scripts/init-env.sh
./scripts/set-auto-create-password.sh
docker compose up -d
./scripts/configure-openai-saml.sh
./scripts/enable-auto-create-login.sh
./scripts/check.sh
```

Then use this URL in OpenAI SSO metadata settings:

```text
https://sso.oaichatgpt.xyz/realms/chatgpt/protocol/saml/descriptor
```

## Full configuration package

If the package includes `.env`, do not run `init-env.sh`; use:

```bash
cd /root/chatgpt-sso-keycloak
docker compose up -d
./scripts/configure-openai-saml.sh
./scripts/enable-auto-create-login.sh
./scripts/check.sh
```

The database volume is not included in the package. Existing Keycloak users and
sessions are not migrated by this package.

## OpenAI side

OpenAI may cache IdP metadata. After moving servers, keep the metadata URL the
same if the hostname remains `sso.oaichatgpt.xyz`.

If you change the hostname, update `.env`, DNS, and the OpenAI SSO metadata URL.
