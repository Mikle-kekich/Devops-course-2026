#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

# Работа из любого каталога репозитория
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         echo "Использование: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует, доставка отменена" >&2
    exit 1
fi
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена" >&2
    exit 1
fi

# 3. Синхронизация (одно SSH-соединение, без интерактивных запросов)
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ ${DRY_RUN} -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
fi
rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run — выход без проверки доступности
if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "Пробный запуск завершён, состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата
if curl -fsS --max-time 10 --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Доставлен коммит $(git -C "${REPO_ROOT}" rev-parse --short HEAD): ${SITE_URL} доступен"
    exit 0
fi
echo "Ошибка: ${SITE_URL} недоступен после доставки" >&2
exit 1
