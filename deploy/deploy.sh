#!/usr/bin/env bash
# 由 GitHub Actions 通过受限 SSH 密钥调用（authorized_keys 中 command= 强制执行本脚本）
#   参数：SSH 传入的命令即镜像 tag（如 sha-abc1234），为空时使用 latest
#   stdin：GHCR 临时 token，用于拉取镜像
# 健康检查失败时自动回滚到上一个 tag
set -euo pipefail

APP_DIR=/opt/cypht
HEALTH_URL=http://127.0.0.1:40050/

TAG="${SSH_ORIGINAL_COMMAND:-${1:-latest}}"
if [[ ! "$TAG" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
    echo "invalid tag: $TAG" >&2
    exit 2
fi

cd "$APP_DIR"
exec 9>"$APP_DIR/.deploy.lock"
flock -w 600 9

# 独立的 docker 配置目录，登录凭据不落在 /root/.docker
DOCKER_CONFIG=$(mktemp -d)
export DOCKER_CONFIG
trap 'rm -rf "$DOCKER_CONFIG"' EXIT

if [ ! -t 0 ]; then
    TOKEN=$(head -n1)
    if [ -n "$TOKEN" ]; then
        printf '%s' "$TOKEN" | docker login ghcr.io -u deploy --password-stdin >/dev/null
    fi
fi

set_tag() {
    if grep -q '^CYPHT_TAG=' .env; then
        sed -i "s|^CYPHT_TAG=.*|CYPHT_TAG=$1|" .env
    else
        echo "CYPHT_TAG=$1" >> .env
    fi
}

healthy() {
    for _ in $(seq 1 30); do
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" || true)
        case "$code" in
            200|302) return 0 ;;
        esac
        sleep 3
    done
    return 1
}

PREV_TAG=$(grep '^CYPHT_TAG=' .env | cut -d= -f2- || true)
PREV_TAG=${PREV_TAG:-latest}

echo "==> deploying ghcr.io/openx123/cypht:$TAG (previous: $PREV_TAG)"
set_tag "$TAG"
if ! docker compose pull -q cypht; then
    echo "==> pull failed, keeping $PREV_TAG" >&2
    set_tag "$PREV_TAG"
    exit 1
fi
docker compose up -d --remove-orphans

if healthy; then
    echo "==> healthy, deployed $TAG"
    docker image prune -f >/dev/null
    exit 0
fi

echo "==> health check failed, rolling back to $PREV_TAG" >&2
docker compose logs --tail 50 cypht >&2 || true
set_tag "$PREV_TAG"
docker compose up -d --remove-orphans
exit 1
