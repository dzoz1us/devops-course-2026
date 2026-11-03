#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo " [OK]  $desc"
    ((PASS++))
  else
    echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
    ((FAIL++))
  fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

SSH_PORT="$(sudo sshd -T | awk '/^port/{print $2}')"
if [[ "$SSH_PORT" != "22" ]]; then
  echo " [OK]  Порт SSH отличен от 22 (текущий: $SSH_PORT)"
  ((PASS++))
else
  echo " [FAIL] Порт SSH равен 22"
  ((FAIL++))
fi

check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика deny incoming" "deny (incoming)" "$(sudo ufw status verbose | grep -o 'deny (incoming)')"

echo "[3] Учётные записи"
awk -F: ' $3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
if sudo nginx -t > /dev/null 2>&1; then
  echo " [OK]  Конфигурация nginx синтаксически корректна"
  ((PASS++))
else
  echo " [FAIL] Ошибка в конфигурации nginx"
  ((FAIL++))
fi

if sudo openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt > /dev/null 2>&1; then
  echo " [OK]  Сертификат действителен более 30 дней"
  ((PASS++))
else
  echo " [FAIL] Сертификат истекает менее чем через 30 дней или отсутствует"
  ((FAIL++))
fi

if [[ -z "$(sudo find /var/www/devops-site -perm -o+w 2>/dev/null)" ]]; then
  echo " [OK]  В каталоге ресурса нет файлов с правом записи для всех"
  ((PASS++))
else
  echo " [FAIL] Найдены файлы с избыточными правами записи!"
  ((FAIL++))
fi

check "Права ключа TLS равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || echo 'нет файла')"

echo "[5] Контейнеризация"
if [[ "$(systemctl is-active docker)" == "active" ]]; then
  echo " [OK]  Служба docker активна"
  ((PASS++))
else
  echo " [FAIL] Служба docker неактивна"
  ((FAIL++))
fi

DB_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo "not_found")
check "Контейнер БД healthy" "healthy" "$DB_HEALTH"

# Проверка, что порты не слушают на 0.0.0.0 (только на 127.0.0.1)
LISTENING_PORTS=$(ss -tln | grep -E ':(5000|5432)\b' | grep -v '127.0.0.1' || true)
if [[ -z "$LISTENING_PORTS" ]]; then
  echo " [OK]  Порты 5000 и 5432 доступны только локально"
  ((PASS++))
else
  echo " [FAIL] Порты доступны извне! $LISTENING_PORTS"
  ((FAIL++))
fi

check "Права файла .env равны 600" "600" "$(stat -c '%a' ~/app/.env 2>/dev/null || echo 'нет файла')"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
