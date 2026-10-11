# 生产部署（mail.yiyongai.cn）

推送到 `master` 后由 [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) 自动完成：

1. 用 `docker/Dockerfile` 构建镜像，推送到 `ghcr.io/openx123/cypht:{latest,sha-xxxxxxx}`
2. 用受限部署密钥 SSH 到香港服务器，执行 `/opt/cypht/deploy.sh sha-xxxxxxx`
3. 脚本拉取镜像、重启容器、健康检查，失败自动回滚到上一个 tag

## 服务器布局（/opt/cypht）

| 文件 | 说明 |
| --- | --- |
| `docker-compose.yaml` | 本目录同名文件的副本 |
| `deploy.sh` | 本目录同名文件的副本 |
| `.env` | 数据库/管理员密码、当前 `CYPHT_TAG`（不入库） |
| `cypht.env` | Cypht 配置，基于 `.env.example` 修改（不入库） |
| `data/` | MariaDB 数据、附件、日志 |

Cypht 只监听 `127.0.0.1:40050`，由 1Panel OpenResty 反代为 `https://mail.yiyongai.cn`。

## GitHub Secrets

`DEPLOY_HOST`、`DEPLOY_USER`、`DEPLOY_SSH_KEY`、`DEPLOY_KNOWN_HOSTS`。
部署公钥在服务器 `authorized_keys` 中以 `command="/opt/cypht/deploy.sh"` 限定，不能执行其他命令。

## 常用操作

```bash
# 手动部署/回滚到指定 tag
/opt/cypht/deploy.sh sha-xxxxxxx < /dev/null

# 修改 Cypht 配置后生效
cd /opt/cypht && docker compose up -d --force-recreate cypht

# 添加用户
docker compose exec cypht php ./scripts/create_account.php 用户名 密码
```

本目录的 `deploy.sh`、`docker-compose.yaml` 修改后需手动同步到服务器（CI 不会覆盖它们）。
