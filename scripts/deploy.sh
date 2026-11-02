#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
    echo "[*] Режим сухого прогона (--dry-run)"
fi

# 2. Проверки по требованиям 4 и 5
# Проверка наличия index.html
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл ${LOCAL_DIR}index.html не найден!" >&2
    exit 1
fi

# Проверка незафиксированных изменений в Git
cd "$(git rev-parse --show-toplevel)"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения!" >&2
    exit 1
fi

# 3. Синхронизация
echo "[*] Начинаю синхронизацию..."
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run завершаем без проверки
if [[ -n "${DRY_RUN}" ]]; then
    echo "[*] Сухой прогон успешно завершен."
    exit 0
fi

# 5. Проверка доступности
echo "[*] Проверка доступности ресурса..."
if ! curl -f --cacert "${CA_CERT}" -s "${SITE_URL}" > /dev/null; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен!" >&2
    exit 1
fi

echo "[+] Деплой успешно завершен. Коммит: $(git rev-parse --short HEAD)"
exit 0
