# ChatGPT SSO Keycloak 部署指南

这个项目用于自建一个 Keycloak SAML Identity Provider，给 ChatGPT / OpenAI Workspace 提供 SSO 登录。

核心组件：

- Keycloak 26：SAML 身份提供方，也就是 IdP
- Postgres 17：Keycloak 数据库
- Caddy 或你自己的 Nginx/OpenResty/1Panel 反向代理：提供公网 HTTPS
- 自定义 Keycloak Provider：可选，用于允许指定邮箱后缀的用户首次登录时自动创建账号

OpenAI / ChatGPT 是 SAML Service Provider，Keycloak 是 SAML Identity Provider。

```text
ChatGPT -> OpenAI SSO -> Keycloak 登录页 -> SAMLResponse -> OpenAI ACS -> ChatGPT
```

注意：ChatGPT 的 SAML 登录是 SP-initiated flow。用户通常先从 ChatGPT 登录页输入企业邮箱，OpenAI 判断该邮箱域名启用了 SSO 后，再跳转到你的 Keycloak。Keycloak 不能直接绕过 OpenAI 的 SAMLRequest 主动登录 ChatGPT。

## 1. 准备条件

服务器需要：

- Linux 服务器一台
- Docker 和 Docker Compose
- 一个已经解析到服务器的域名，例如 `sso.example.com`
- 服务器 80/443 端口可用于 HTTPS，或已有反向代理可以转发到本项目
- OpenAI / ChatGPT Workspace 管理权限
- 一个已经在 OpenAI Workspace 里验证过的邮箱域名或子域名

建议：

- 使用独立子域名作为 IdP 地址，例如 `sso.example.com`
- 不要把 `.env` 提交到 Git
- 生产环境优先使用每个用户自己的密码，不建议长期使用共享密码

## 2. 克隆项目

```bash
git clone <your-repo-url> chatgpt-sso-keycloak
cd chatgpt-sso-keycloak
```

如果你是在当前服务器继续维护，直接进入项目目录即可：

```bash
cd /path/to/chatgpt-sso-keycloak
```

## 3. 配置 DNS

给 Keycloak 公网地址配置 DNS：

```text
Type: A
Name: sso
Value: <your-server-ip>
```

如果你使用的是 Cloudflare、DNSPod、阿里云、腾讯云等 DNS 服务商，实际填写方式通常是：

```text
主机记录: sso
记录类型: A
记录值: 服务器公网 IP
```

验证解析：

```bash
dig +short sso.example.com
```

返回服务器公网 IP 即可。

## 4. OpenAI 域名验证

在 OpenAI Workspace 的 SSO / Domain verification 页面验证你的邮箱域名。

如果验证根域名 `example.com`，TXT 记录通常是：

```text
Type: TXT
Name: @
Value: openai-domain-verification=...
```

如果验证子域名 `team.example.com`，并且你的 DNS 区域是 `example.com`，TXT 记录应该是：

```text
Type: TXT
Name: team
Value: openai-domain-verification=...
```

不要把 `team.example.com` 的 TXT 错加到 `@`，否则验证的是根域名，不是子域名。

检查 TXT：

```bash
dig +short TXT team.example.com
```

## 5. 创建 .env

复制示例配置：

```bash
cp .env.example .env
chmod 600 .env
```

也可以用脚本生成随机 Keycloak/Postgres 密码：

```bash
./scripts/init-env.sh
```

如果 `.env` 已存在，脚本不会覆盖它。

编辑 `.env`：

```bash
nano .env
```

最小配置示例：

```env
KEYCLOAK_HOSTNAME=sso.example.com
KEYCLOAK_PUBLIC_URL=https://sso.example.com
KEYCLOAK_LOCAL_URL=http://127.0.0.1:18081
KEYCLOAK_REALM=chatgpt

KEYCLOAK_ADMIN_USERNAME=admin
KEYCLOAK_ADMIN_PASSWORD=replace-with-a-generated-secret
POSTGRES_PASSWORD=replace-with-a-generated-secret

ACME_EMAIL=admin@example.com

OPENAI_SP_METADATA_URL=https://external.auth.openai.com/sso/saml/<openai-sp-entity-id>/metadata.xml
OPENAI_SP_ENTITY_ID=<openai-sp-entity-id>
OPENAI_ACS_URL=https://external.auth.openai.com/sso/saml/acs/<openai-sp-entity-id>

ALLOWED_EMAIL_DOMAIN=example.com
ALLOWED_EMAIL_DOMAINS=example.com,team.example.com
AUTO_CREATE_USER_PASSWORD=replace-with-a-shared-initial-password
```

字段说明：

```text
KEYCLOAK_HOSTNAME       Keycloak 对外域名，不带 https://
KEYCLOAK_PUBLIC_URL     Keycloak 对外完整 URL
KEYCLOAK_LOCAL_URL      本机访问 Keycloak 的地址，默认 http://127.0.0.1:18081
KEYCLOAK_REALM          Keycloak realm 名称，默认 chatgpt
OPENAI_SP_ENTITY_ID     OpenAI SAML Step 2 给出的 Service provider entity ID
OPENAI_ACS_URL          OpenAI SAML Step 2 给出的 ACS URL
OPENAI_SP_METADATA_URL  OpenAI SAML Step 2 给出的 metadata.xml URL
ALLOWED_EMAIL_DOMAINS   允许登录或自动创建的邮箱后缀，多个用英文逗号分隔
AUTO_CREATE_USER_PASSWORD 自动创建用户时使用的初始共享密码
```

`.env` 包含密码和真实 OpenAI SAML ID，不要提交到 Git。

## 6. 启动 Keycloak

启动 Postgres 和 Keycloak：

```bash
docker compose up -d postgres keycloak
```

查看容器状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f keycloak
```

本项目默认把 Keycloak 只暴露到本机：

```text
127.0.0.1:18081 -> keycloak:8080
```

这样更适合放在 Nginx/OpenResty/1Panel/Caddy 后面。

## 7. 配置 HTTPS 反向代理

### 方案 A：使用项目自带 Caddy

如果服务器 80/443 没有被占用，可以直接启用 Caddy：

```bash
docker compose --profile caddy up -d
```

Caddy 会读取 `Caddyfile`，自动申请证书并反代到 Keycloak。

`Caddyfile` 默认逻辑：

```text
sso.example.com -> keycloak:8080
```

### 方案 B：使用已有 Nginx / OpenResty / 1Panel

如果服务器已经有反代服务，把公网域名转发到：

```text
http://127.0.0.1:18081
```

Nginx 示例：

```nginx
server {
    listen 443 ssl http2;
    server_name sso.example.com;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:18081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

Keycloak 已在 `docker-compose.yml` 中启用：

```text
KC_PROXY_HEADERS=xforwarded
KC_HTTP_ENABLED=true
```

所以反代时要保留 `X-Forwarded-Proto` 和 `Host`。

## 8. 创建 OpenAI SAML Client

在 OpenAI Workspace 的 SSO 配置页面，Step 2 会给你三个值：

```text
Service provider metadata URL
Assertion consumer service (ACS) URL
Service provider entity ID
```

把它们填入 `.env`：

```env
OPENAI_SP_METADATA_URL=https://external.auth.openai.com/sso/saml/<id>/metadata.xml
OPENAI_SP_ENTITY_ID=<id>
OPENAI_ACS_URL=https://external.auth.openai.com/sso/saml/acs/<id>
```

然后运行：

```bash
./scripts/configure-openai-saml.sh
```

脚本会自动：

- 创建 `chatgpt` realm
- 创建或更新 OpenAI SAML client
- 配置 SAML 签名
- 配置 OpenAI 需要的 SAML attributes

SAML attributes 映射如下：

```text
id        <- email
email     <- email
firstName <- firstName
lastName  <- lastName
```

## 9. 在 OpenAI 填写 IdP 信息

OpenAI Step 3 需要 Identity Provider 信息。

优先使用 metadata URL：

```text
https://sso.example.com/realms/chatgpt/protocol/saml/descriptor
```

如果 OpenAI 后台要求手动填写，则使用：

```text
SSO URL:
https://sso.example.com/realms/chatgpt/protocol/saml

Entity ID:
https://sso.example.com/realms/chatgpt

Certificate:
从 metadata XML 里复制 X509Certificate
```

检查 metadata 是否能公网访问：

```bash
curl -I https://sso.example.com/realms/chatgpt/protocol/saml/descriptor
```

应该返回 `200`。

## 10. 检查部署

运行项目自带检查脚本：

```bash
./scripts/check.sh
```

它会检查：

- 本机 Keycloak realm 是否可访问
- 本机 SAML metadata 是否可访问
- DNS A 记录是否指向当前服务器
- OpenAI Step 3 应该填写的 metadata URL

也可以手动检查：

```bash
curl -fsS http://127.0.0.1:18081/realms/chatgpt >/dev/null && echo ok
curl -fsS https://sso.example.com/realms/chatgpt/protocol/saml/descriptor >/dev/null && echo ok
```

## 11. 创建用户

### 手动创建单个用户

```bash
./scripts/create-user.sh alice@example.com Alice Zhang
```

脚本会提示输入用户密码。

邮箱必须属于 `.env` 里的允许域名：

```env
ALLOWED_EMAIL_DOMAINS=example.com,team.example.com
```

### 批量创建用户

准备 CSV：

```csv
email,firstName,lastName
alice@example.com,Alice,Zhang
bob@example.com,Bob,Wang
```

导入：

```bash
./scripts/create-users-bulk.sh users.csv
```

要求首次登录修改密码：

```bash
./scripts/create-users-bulk.sh --force-password-change users.csv
```

## 12. 启用自动创建用户

自动创建用户的作用：

当用户在 Keycloak 登录页输入一个允许域名下的邮箱，且该用户还不存在时，Keycloak 自动创建这个用户，并用 `AUTO_CREATE_USER_PASSWORD` 校验本次登录密码。

构建 Provider：

```bash
./scripts/build-provider.sh
```

设置自动创建用户的共享初始密码：

```bash
./scripts/set-auto-create-password.sh
```

重启 Keycloak：

```bash
docker compose up -d --force-recreate keycloak
```

启用自定义登录 Flow：

```bash
./scripts/enable-auto-create-login.sh
```

启用后，用户可以用：

```text
邮箱: user@example.com
密码: AUTO_CREATE_USER_PASSWORD
```

首次通过 Keycloak 登录。生产环境建议后续改成每个用户独立密码或强制修改密码。

## 13. 新增一个 ChatGPT Workspace

同一个 Keycloak realm 可以同时接多个 OpenAI / ChatGPT Workspace。

OpenAI 新 Workspace 会给新的 SAML 参数，例如：

```text
ACS URL:
https://external.auth.openai.com/sso/saml/acs/<new-openai-sp-entity-id>

Service provider entity ID:
<new-openai-sp-entity-id>

Metadata URL:
https://external.auth.openai.com/sso/saml/<new-openai-sp-entity-id>/metadata.xml
```

直接运行：

```bash
./scripts/configure-openai-saml.sh \
  <new-openai-sp-entity-id> \
  https://external.auth.openai.com/sso/saml/acs/<new-openai-sp-entity-id> \
  https://external.auth.openai.com/sso/saml/<new-openai-sp-entity-id>/metadata.xml
```

这个脚本会新增或更新对应 client，不会删除已有 Workspace 的 client。

然后把新 Workspace 使用的邮箱域名加入 `.env`：

```env
ALLOWED_EMAIL_DOMAINS=example.com,team.example.com,new-team.example.com
```

重启 Keycloak 让环境变量生效：

```bash
docker compose up -d --force-recreate keycloak
```

OpenAI 新 Workspace 里继续填写同一个 IdP metadata URL：

```text
https://sso.example.com/realms/chatgpt/protocol/saml/descriptor
```

## 14. 新增邮箱子域名

如果你想让不同 Workspace 使用不同邮箱后缀，推荐用子域名：

```text
team1.example.com
team2.example.com
```

OpenAI 里分别验证这些子域名。

DNS TXT 示例：

```text
要验证 team1.example.com：
Name: team1
Value: openai-domain-verification=...
```

然后在 `.env` 里允许这些邮箱后缀：

```env
ALLOWED_EMAIL_DOMAINS=team1.example.com,team2.example.com
```

用户邮箱应类似：

```text
alice@team1.example.com
bob@team2.example.com
```

## 15. 用户如何登录 ChatGPT

正常流程：

1. 打开 `https://chatgpt.com`
2. 选择登录
3. 输入已启用 SSO 的企业邮箱
4. OpenAI 跳转到你的 Keycloak 域名
5. 在 Keycloak 输入邮箱和密码
6. 登录成功后回到 ChatGPT

如果 OpenAI 后台提供 Application login URL，可以配置为门户入口；但它只是帮助用户进入 ChatGPT 的 SSO 起点，不能替代 SAMLRequest。

不要把邮箱和密码放进 URL。URL 会进入浏览器历史、代理日志、访问日志和 Referer，容易泄露。

## 16. 常见问题

### metadata URL 打不开

检查：

```bash
docker compose ps
docker compose logs --tail=100 keycloak
curl -I http://127.0.0.1:18081/realms/chatgpt/protocol/saml/descriptor
curl -I https://sso.example.com/realms/chatgpt/protocol/saml/descriptor
```

如果本机能打开、公网打不开，问题通常在 DNS、HTTPS 证书或反向代理。

### OpenAI 提示 SAML attribute 缺失

重新运行：

```bash
./scripts/configure-openai-saml.sh
```

确认 attributes 是：

```text
id
email
firstName
lastName
```

其中 `id` 默认映射到用户邮箱。

### Keycloak 提示 Restart login cookie not found

常见原因：

- 浏览器禁用了该域名 Cookie
- 登录流程停留太久，临时 Cookie 过期
- 从旧的回调页面反复刷新
- 反向代理 Host 或 X-Forwarded-Proto 配置不正确

处理方式：

- 允许 `sso.example.com` 保存 Cookie
- 删除该站点 Cookie 后重新从 ChatGPT 发起登录
- 确认反代传了 `Host` 和 `X-Forwarded-Proto: https`

### 用户密码错误

如果是手动创建用户，重新设置密码：

```bash
./scripts/create-user.sh alice@example.com Alice Zhang
```

如果是自动创建用户，确认用户输入的是 `.env` 里的：

```env
AUTO_CREATE_USER_PASSWORD=...
```

修改后重启 Keycloak：

```bash
docker compose up -d --force-recreate keycloak
```

### 更换 OpenAI Workspace 后所有邮箱仍跳 SSO

这是 OpenAI 侧域名绑定导致的。要让根域名邮箱恢复普通注册/登录，需要在旧 Workspace 的 SSO/域名配置里解除或删除对应域名绑定。

推荐做法：

- 根域名 `example.com` 保持普通注册
- SSO 使用子域名邮箱，例如 `team.example.com`
- 新 Workspace 只验证并绑定 `team.example.com`

## 17. 维护命令

停止：

```bash
docker compose down
```

重启：

```bash
docker compose up -d
```

查看日志：

```bash
docker compose logs -f keycloak
```

备份数据库卷：

```bash
docker compose exec postgres pg_dump -U keycloak keycloak > keycloak-backup.sql
```

恢复数据库前请先停止 Keycloak，并确认目标环境为空库。

## 18. 安全建议

- 不要提交 `.env`
- 不要把密码放进 URL、二维码或公开文档
- 不要把 Keycloak 管理后台暴露给不可信网络
- 生产环境建议启用 MFA
- 建议每个用户使用独立密码
- 共享初始密码只适合临时 onboarding
- 离职或不再授权的用户应在 Keycloak 和 OpenAI Workspace 两边都移除

