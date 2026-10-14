#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
SSH_PORT="$(sudo sshd -T | awk '/^port /{print $2; exit}')"
check "Порт SSH отличен от 22"             "yes" "$([[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]] && echo yes || echo "no (port=$SSH_PORT)")"
check "Число попыток аутентификации 3"     "3"   "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Входящий трафик по умолчанию запрещён" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
CERT_DAYS="${CERT_DAYS:-30}"   # порог срока действия сертификата, сут.
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx корректна (nginx -t)" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действителен ещё ${CERT_DAYS} сут." "0" "$(openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend $((CERT_DAYS * 86400)) >/dev/null 2>&1; echo $?)"
check "В каталоге ресурса нет файлов с записью для всех" "0" "$(find /var/www/devops-site -perm -o+w 2>/dev/null | wc -l)"
check "Права закрытого ключа TLS 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)"
echo "[5] Контейнеризация"
APP_DIR="${APP_DIR:-$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)/app}"   # каталог проекта
DB_CONTAINER="${DB_CONTAINER:-app-db-1}"                                            # контейнер СУБД
check "Служба docker активна" "active" "$(systemctl is-active docker)"
check "Контейнер СУБД в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' "${DB_CONTAINER}" 2>/dev/null)"
check "Порты 5000 и 5432 слушаются только на 127.0.0.1" "0" "$(ss -tln | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/' | wc -l)"
check "Права файла .env равны 600" "600" "$(stat -c '%a' "${APP_DIR}/.env" 2>/dev/null)"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
