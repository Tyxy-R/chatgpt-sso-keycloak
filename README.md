# ChatGPT SSO Keycloak

这是一个自建 ChatGPT / OpenAI Workspace SSO 的 Keycloak 部署项目。

最简单理解：

```text
用户打开 ChatGPT -> 输入企业邮箱 -> 跳到你的 SSO 域名 -> 登录成功 -> 回到 ChatGPT
```

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Tyxy-R/chatgpt-sso-keycloak,Tyxy-R/codex-referral-risk-research&type=Date)](https://www.star-history.com/#Tyxy-R/chatgpt-sso-keycloak&Tyxy-R/codex-referral-risk-research&Date)

## 配套研究工具

如果你需要在这个 SSO / Keycloak 部署基础上做 seed 登录、并发邀请、邀请结果导出、invitee auth 获取和激活遥测研究，请使用配套仓库：

https://github.com/Tyxy-R/codex-referral-risk-research

该配套仓库假设本项目的 Keycloak SAML IdP 已经部署完成，并且目标邮箱域名已经在 OpenAI Workspace 中完成验证。

## 最简单部署

准备好这些东西：

- 一台 Linux 服务器
- Docker 和 Docker Compose
- 一个 SSO 域名，例如 `sso.example.com`
- 一个邮箱域名或子域名，例如 `team.example.com`
- OpenAI Workspace 后台 SAML Step 2 里的 `Service provider entity ID`

先把 SSO 域名解析到服务器：

```text
sso.example.com -> 服务器公网 IP
```

然后在服务器运行：

```bash
git clone <your-repo-url> chatgpt-sso-keycloak
cd chatgpt-sso-keycloak
./scripts/quick-deploy.sh
```

脚本会问你几个问题：

```text
Public SSO host:
填 sso.example.com

Allowed email domains:
填 team.example.com

OpenAI service provider entity ID:
填 OpenAI Step 2 里的 Service provider entity ID

Email for HTTPS certificates:
填你的管理员邮箱

Start bundled Caddy for HTTPS?
如果服务器 80/443 没有被占用，填 yes；如果你用 1Panel/Nginx/OpenResty，直接回车

Shared initial password:
填用户第一次登录 SSO 用的初始密码
```

脚本完成后，会输出这个地址：

```text
https://sso.example.com/realms/chatgpt/protocol/saml/descriptor
```

把它填到 OpenAI 的 SAML / SSO 配置页面，也就是 IdP metadata URL。

## 一条命令部署

也可以不进入交互模式：

```bash
./scripts/quick-deploy.sh \
  --host sso.example.com \
  --email-domains team.example.com \
  --openai-id <openai-sp-entity-id> \
  --acme-email admin@example.com \
  --auto-password 'ChangeMe123!' \
  --caddy
```

如果你不用项目自带 Caddy，而是用 1Panel/Nginx/OpenResty，不要加 `--caddy`。把反向代理目标设为：

```text
http://127.0.0.1:18081
```

反代必须带上：

```text
Host
X-Forwarded-Proto
X-Forwarded-For
```

## OpenAI 里怎么填

OpenAI Step 2 会给三个值：

```text
Service provider metadata URL
Assertion consumer service (ACS) URL
Service provider entity ID
```

部署脚本只需要你输入：

```text
Service provider entity ID
```

因为 ACS URL 和 metadata URL 可以自动拼出来。

OpenAI Step 3 需要你填 Keycloak 的 IdP metadata URL：

```text
https://你的SSO域名/realms/chatgpt/protocol/saml/descriptor
```

例如：

```text
https://sso.example.com/realms/chatgpt/protocol/saml/descriptor
```

SAML attributes 脚本会自动配置：

```text
id        <- email
email     <- email
firstName <- firstName
lastName  <- lastName
```

## 新增一个 Workspace

以后新增 ChatGPT Workspace，不需要重新部署。

拿到新 Workspace 的 `Service provider entity ID` 后运行：

```bash
./scripts/add-workspace.sh <openai-sp-entity-id>
```

如果这个 Workspace 还使用新的邮箱后缀，一起加上：

```bash
./scripts/add-workspace.sh <openai-sp-entity-id> sso2.example.com
```

多个邮箱后缀用英文逗号：

```bash
./scripts/add-workspace.sh <openai-sp-entity-id> team1.example.com,team2.example.com
```

脚本会自动：

- 新增 Keycloak SAML client
- 自动拼 OpenAI ACS URL
- 自动拼 OpenAI metadata URL
- 追加邮箱后缀到 `.env`
- 必要时重启 Keycloak

新增后，OpenAI Step 3 仍然填同一个 IdP metadata URL：

```text
https://你的SSO域名/realms/chatgpt/protocol/saml/descriptor
```

## 用户怎么登录

正常流程：

1. 打开 `https://chatgpt.com`
2. 输入已经启用 SSO 的邮箱
3. OpenAI 自动跳转到你的 SSO 域名
4. 输入邮箱和 SSO 密码
5. 登录成功后回到 ChatGPT

不要把邮箱和密码放进 URL。URL 会进入浏览器历史、代理日志和访问日志。

## 新增用户

如果启用了自动创建用户，用户第一次登录时会自动创建账号。

邮箱必须属于 `.env` 里的：

```env
ALLOWED_EMAIL_DOMAINS=team.example.com
```

用户初始密码是：

```env
AUTO_CREATE_USER_PASSWORD=你部署时设置的密码
```

也可以手动创建用户：

```bash
./scripts/create-user.sh alice@team.example.com Alice Zhang
```

批量导入：

```bash
./scripts/create-users-bulk.sh users.csv
```

CSV 格式：

```csv
email,firstName,lastName
alice@team.example.com,Alice,Zhang
bob@team.example.com,Bob,Wang
```

## 验证部署

运行：

```bash
./scripts/check.sh
```

手动检查 metadata：

```bash
curl -I https://sso.example.com/realms/chatgpt/protocol/saml/descriptor
```

看到 `200` 就说明公网 metadata 可访问。

## 反向代理示例

如果你不用 Caddy，Nginx/OpenResty 可以这样配：

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

## 子域名邮箱怎么验证

如果 OpenAI 要你验证 `team.example.com`，并且你的 DNS 区域是 `example.com`，TXT 应该这样加：

```text
Type: TXT
Name: team
Value: openai-domain-verification=...
```

如果 OpenAI 要你验证根域名 `example.com`：

```text
Type: TXT
Name: @
Value: openai-domain-verification=...
```

验证：

```bash
dig +short TXT team.example.com
```

## 常用命令

查看状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f keycloak
```

重启：

```bash
docker compose up -d --force-recreate keycloak
```

停止：

```bash
docker compose down
```

备份数据库：

```bash
docker compose exec postgres pg_dump -U keycloak keycloak > keycloak-backup.sql
```

## 常见问题

### OpenAI 提示 SAML attribute 缺失

重新跑：

```bash
./scripts/configure-openai-saml.sh
```

### Keycloak 提示 Restart login cookie not found

通常是浏览器 Cookie 或反代问题。

处理：

- 允许 SSO 域名保存 Cookie
- 删除这个站点的 Cookie
- 从 ChatGPT 重新发起登录
- 确认反代传了 `Host` 和 `X-Forwarded-Proto: https`

### 用户密码错误

如果是自动创建用户，确认用户输入的是 `.env` 里的：

```env
AUTO_CREATE_USER_PASSWORD=...
```

如果要改密码：

```bash
./scripts/set-auto-create-password.sh
docker compose up -d --force-recreate keycloak
```

### 换 Workspace 后，域名邮箱还是强制跳旧 SSO

这是 OpenAI 侧域名绑定造成的。需要在旧 Workspace 解除该域名的 SSO/域名绑定。

更推荐：

- 根域名邮箱保留普通注册
- SSO 使用子域名邮箱，例如 `team.example.com`
- 新 Workspace 只验证这个子域名

## 重要安全提醒

- 不要提交 `.env`
- 不要把密码放到 URL 里
- 不要公开 Keycloak 管理员密码
- 生产环境建议启用 MFA
- 共享初始密码只适合临时 onboarding
- 正式使用建议给每个用户单独密码
- 离职或不再授权的用户应在 Keycloak 和 OpenAI Workspace 两边都移除

## 19. License

MIT License. See [LICENSE](LICENSE).
