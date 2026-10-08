#!/usr/bin/env bash
# ==============================================================================
# МОДУЛЬ 10: РЕЗЕРВНОЕ КОПИРОВАНИЕ, СТАРТ И CLI-ИНТЕРФЕЙС УПРАВЛЕНИЯ
# ==============================================================================

setup_backups_and_start() {
    print_step_header "10/11" "РЕЗЕРВНОЕ КОПИРОВАНИЕ, СТАРТ И АВТО-ИНИЦИАЛИЗАЦИЯ"

    if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
        log_info "Настройка автоматического горячего бэкапа Vaultwarden (SQLite3)..."
        cat << 'EOF_BACKUP' > "${APP_DIR}/backup_vaultwarden.sh"
#!/usr/bin/env bash
set -euo pipefail

if [ -f /opt/homelab/.env ]; then
    # shellcheck disable=SC1091
    source /opt/homelab/.env
fi
SAVE_DIR="${SAVED_SAVE_DIR:-/opt/homelab/save}"
BACKUP_DIR="${SAVE_DIR}/backups/vaultwarden"
DB_SRC="${SAVED_VAULT_DATA_DIR:-/opt/homelab/vaultwarden}/db.sqlite3"
[ ! -f "${DB_SRC}" ] && DB_SRC="${SAVE_DIR}/services/vaultwarden/db.sqlite3"
DATA_DIR=$(dirname "${DB_SRC}")
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
TEMP_DIR=$(mktemp -d)

trap 'rm -rf "${TEMP_DIR}"' EXIT

mkdir -p "${BACKUP_DIR}"

if [ -f "${DB_SRC}" ]; then
    if ! python3 -c "import sqlite3, sys; s = sqlite3.connect(sys.argv[1]); b = sqlite3.connect(sys.argv[2]); s.backup(b); b.close(); s.close()" "${DB_SRC}" "${TEMP_DIR}/db.sqlite3" 2>/dev/null; then
        sqlite3 "${DB_SRC}" ".backup '${TEMP_DIR}/db.sqlite3'" 2>/dev/null || true
    fi

    [ -d "${DATA_DIR}/attachments" ] && cp -r "${DATA_DIR}/attachments" "${TEMP_DIR}/"
    [ -d "${DATA_DIR}/sends" ] && cp -r "${DATA_DIR}/sends" "${TEMP_DIR}/"
    [ -f "${DATA_DIR}/rsa_key.pem" ] && cp -f "${DATA_DIR}/rsa_key.pem" "${TEMP_DIR}/"
    [ -f "${DATA_DIR}/config.json" ] && cp -f "${DATA_DIR}/config.json" "${TEMP_DIR}/"

    tar -czf "${BACKUP_DIR}/vaultwarden_backup_${DATE_TAG}.tar.gz" -C "${TEMP_DIR}" .
    chmod 600 "${BACKUP_DIR}/vaultwarden_backup_${DATE_TAG}.tar.gz" 2>/dev/null || true
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true
    chown -R "${SAVED_TARGET_USER:-root}:${USER_GID:-0}" "${BACKUP_DIR}" 2>/dev/null || true
    find "${BACKUP_DIR}" -type f -name "vaultwarden_backup_*.tar.gz" -mtime +14 -delete 2>/dev/null || true
    BKP_SIZE=$(du -h "${BACKUP_DIR}/vaultwarden_backup_${DATE_TAG}.tar.gz" 2>/dev/null | awk '{print $1}')
    /usr/local/bin/homelab-notify "Резервное копирование" "Успешно создан ночной бэкап Vaultwarden (${BKP_SIZE})" "OK" 2>/dev/null || true
fi
EOF_BACKUP
        chmod 750 "${APP_DIR}/backup_vaultwarden.sh"

        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            cat <<EOF_BKP_SVC > /etc/systemd/system/vaultwarden-backup.service
[Unit]
Description=Vaultwarden Database Backup
After=network.target

[Service]
Type=oneshot
ExecStart=${APP_DIR}/backup_vaultwarden.sh
EOF_BKP_SVC

            cat <<EOF_BKP_TMR > /etc/systemd/system/vaultwarden-backup.timer
[Unit]
Description=Daily Vaultwarden Database Backup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF_BKP_TMR

            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable --now vaultwarden-backup.timer >/dev/null 2>&1 || true
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            mkdir -p /etc/crontabs
            if ! grep -q 'backup_vaultwarden.sh' /etc/crontabs/root 2>/dev/null; then
                echo "0 3 * * * ${APP_DIR}/backup_vaultwarden.sh >/dev/null 2>&1" >> /etc/crontabs/root
            fi
            touch /etc/crontabs/cron.update 2>/dev/null || true
            rc-update add crond default >/dev/null 2>&1 || true
            rc-service crond status >/dev/null 2>&1 || rc-service crond start >/dev/null 2>&1 || true
        fi
    fi

    if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
        log_info "Настройка автоматического горячего бэкапа Gitea (dump в шару)..."
        mkdir -p "${SAVE_DIR}/backups/gitea"
        chown -R "${USER_UID}:${USER_GID}" "${SAVE_DIR}/backups/gitea" 2>/dev/null || true

        cat << 'EOF_GITEA_BKP' > "${APP_DIR}/backup_gitea.sh"
#!/usr/bin/env bash
set -euo pipefail

if [ -f /opt/homelab/.env ]; then
    # shellcheck disable=SC1091
    source /opt/homelab/.env
fi
SAVE_DIR="${SAVED_SAVE_DIR:-/opt/homelab/save}"
BACKUP_DIR="${SAVE_DIR}/backups/gitea"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
DUMP_NAME="gitea_backup_${DATE_TAG}.zip"

mkdir -p "${BACKUP_DIR}"

if docker inspect -f '{{.State.Status}}' gitea 2>/dev/null | grep -q "running"; then
    docker exec -u "${USER_UID:-1000}:${USER_GID:-1000}" gitea gitea dump --tempdir /tmp -f "/backup/${DUMP_NAME}" -c /data/gitea/conf/app.ini >/dev/null 2>&1 || \
    docker exec -u git gitea gitea dump --tempdir /tmp -f "/backup/${DUMP_NAME}" -c /data/gitea/conf/app.ini >/dev/null 2>&1 || true

    chown -R "${SAVED_TARGET_USER:-root}:${USER_GID:-0}" "${BACKUP_DIR}" 2>/dev/null || true
    chmod 640 "${BACKUP_DIR}"/gitea_backup_*.zip 2>/dev/null || true
    chmod 750 "${BACKUP_DIR}" 2>/dev/null || true
    find "${BACKUP_DIR}" -type f -name "gitea_backup_*.zip" -mtime +14 -delete 2>/dev/null || true
    BKP_SIZE=$(du -h "${BACKUP_DIR}/${DUMP_NAME}" 2>/dev/null | awk '{print $1}')
    /usr/local/bin/homelab-notify "Резервное копирование" "Успешно создан ночной бэкап Gitea (${BKP_SIZE})" "OK" 2>/dev/null || true
fi
EOF_GITEA_BKP
        chmod 750 "${APP_DIR}/backup_gitea.sh"

        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            cat <<EOF_GITEA_BKP_SVC > /etc/systemd/system/gitea-backup.service
[Unit]
Description=Gitea Repositories & Database Backup
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=${APP_DIR}/backup_gitea.sh
EOF_GITEA_BKP_SVC

            cat <<EOF_GITEA_BKP_TMR > /etc/systemd/system/gitea-backup.timer
[Unit]
Description=Daily Gitea Database and Repositories Backup Timer

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF_GITEA_BKP_TMR

            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable --now gitea-backup.timer >/dev/null 2>&1 || true
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            mkdir -p /etc/crontabs
            if ! grep -q 'backup_gitea.sh' /etc/crontabs/root 2>/dev/null; then
                echo "30 3 * * * ${APP_DIR}/backup_gitea.sh >/dev/null 2>&1" >> /etc/crontabs/root
            fi
            touch /etc/crontabs/cron.update 2>/dev/null || true
            rc-update add crond default >/dev/null 2>&1 || true
            rc-service crond status >/dev/null 2>&1 || rc-service crond start >/dev/null 2>&1 || true
        fi
    fi

    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        cat <<'EOF_NAVI_BKP' > "${APP_DIR}/backup_navidrome.sh"
#!/usr/bin/env bash
set -euo pipefail

if [ -f /opt/homelab/.env ]; then
    # shellcheck disable=SC1091
    source /opt/homelab/.env
fi
SAVE_DIR="${SAVED_SAVE_DIR:-/opt/homelab/save}"
BACKUP_DIR="${SAVE_DIR}/backups/navidrome"
DB_SRC="/opt/homelab/configs/navidrome/navidrome.db"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
DUMP_NAME="navidrome_backup_${DATE_TAG}.sql.gz"

mkdir -p "${BACKUP_DIR}"

if [ -f "${DB_SRC}" ]; then
    TEMP_FILE=$(mktemp)
    if ! python3 -c "import sqlite3, sys; s = sqlite3.connect(sys.argv[1]); b = sqlite3.connect(sys.argv[2]); s.backup(b); b.close(); s.close()" "${DB_SRC}" "${TEMP_FILE}" 2>/dev/null; then
        sqlite3 "${DB_SRC}" ".backup '${TEMP_FILE}'" 2>/dev/null || cp -f "${DB_SRC}" "${TEMP_FILE}"
    fi
    gzip -c "${TEMP_FILE}" > "${BACKUP_DIR}/${DUMP_NAME}"
    rm -f "${TEMP_FILE}"
    chown -R "${SAVED_TARGET_USER:-root}:${USER_GID:-0}" "${BACKUP_DIR}" 2>/dev/null || true
    chmod 640 "${BACKUP_DIR}"/navidrome_backup_*.sql.gz 2>/dev/null || true
    chmod 750 "${BACKUP_DIR}" 2>/dev/null || true
    find "${BACKUP_DIR}" -type f -name "navidrome_backup_*.sql.gz" -mtime +14 -delete 2>/dev/null || true
    BKP_SIZE=$(du -h "${BACKUP_DIR}/${DUMP_NAME}" 2>/dev/null | awk '{print $1}')
    /usr/local/bin/homelab-notify "Резервное копирование" "Успешно создан ночной бэкап Navidrome (${BKP_SIZE})" "OK" 2>/dev/null || true
fi
EOF_NAVI_BKP
        chmod 750 "${APP_DIR}/backup_navidrome.sh"

        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            cat <<EOF_NAVI_BKP_SVC > /etc/systemd/system/navidrome-backup.service
[Unit]
Description=Navidrome Music Database Backup
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=${APP_DIR}/backup_navidrome.sh
EOF_NAVI_BKP_SVC

            cat <<EOF_NAVI_BKP_TMR > /etc/systemd/system/navidrome-backup.timer
[Unit]
Description=Daily Navidrome Database Backup Timer

[Timer]
OnCalendar=*-*-* 03:45:00
Persistent=true

[Install]
WantedBy=timers.target
EOF_NAVI_BKP_TMR

            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable --now navidrome-backup.timer >/dev/null 2>&1 || true
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            mkdir -p /etc/crontabs
            if ! grep -q 'backup_navidrome.sh' /etc/crontabs/root 2>/dev/null; then
                echo "45 3 * * * ${APP_DIR}/backup_navidrome.sh >/dev/null 2>&1" >> /etc/crontabs/root
            fi
            touch /etc/crontabs/cron.update 2>/dev/null || true
        fi
    fi

    cd "${APP_DIR}"

    if [ "${IS_UPGRADE_MODE:-0}" -ne 1 ]; then
        log_info "Загрузка Docker-образов стека с поддержкой зеркал и докачки..."
        local IMAGES=()
        if dc config --images >/dev/null 2>&1; then
            while IFS= read -r line; do
                [ -n "$line" ] && IMAGES+=("$line")
            done < <(dc config --images 2>/dev/null | sort -u)
        fi
        [ ${#IMAGES[@]} -eq 0 ] && IMAGES=("caddy:alpine" "servercontainers/samba:latest" "adguard/adguardhome:latest" "metacubex/mihomo:latest" "vaultwarden/server:latest" "gitea/gitea:latest" "linuxserver/qbittorrent:latest" "alexta69/metube:latest" "deluan/navidrome:latest" "containrrr/watchtower:latest" "willfarrell/autoheal:latest" "amir20/dozzle:latest")

        for img in "${IMAGES[@]}"; do
            if docker image inspect "${img}" >/dev/null 2>&1; then
                log_ok "Образ ${img} уже готов"
                continue
            fi

            local PULL_DONE=0
            for att in 1 2; do
                log_info "Загрузка ${img} (попытка ${att}/2)..."
                if docker pull "${img}"; then
                    PULL_DONE=1
                    log_ok "Образ ${img} успешно загружен"
                    break
                else
                    log_warn "Сбой штатной загрузки ${img} (попытка ${att}). Проверка зеркал..."
                    sleep 2
                fi
            done

            # 2. Прямой pull через префиксы проверенных российских зеркал Docker Hub
            if [ $PULL_DONE -eq 0 ]; then
                local PREFIX_IMG="${img}"
                [[ ! "${PREFIX_IMG}" =~ / ]] && PREFIX_IMG="library/${PREFIX_IMG}"
                for mirror in "dockerhub.timeweb.cloud" "dockerproxy.net" "docker.m.daocloud.io"; do
                    log_info "Прямая загрузка ${img} через проверенное зеркало (${mirror})..."
                    if docker pull "${mirror}/${PREFIX_IMG}"; then
                        docker tag "${mirror}/${PREFIX_IMG}" "${img}" 2>/dev/null || true
                        docker rmi "${mirror}/${PREFIX_IMG}" >/dev/null 2>&1 || true
                        PULL_DONE=1
                        log_ok "Образ ${img} успешно получен через зеркало ${mirror}"
                        break
                    fi
                done
            fi

            # 3. Прямой fallback на независимые реестры (ghcr.io / lscr.io)
            if [ $PULL_DONE -eq 0 ]; then
                local FALLBACK_IMG=""
                case "${img}" in
                    *alexta69/metube*) FALLBACK_IMG="ghcr.io/alexta69/metube:latest" ;;
                    *linuxserver/qbittorrent*) FALLBACK_IMG="lscr.io/linuxserver/qbittorrent:latest" ;;
                    *metacubex/mihomo*) FALLBACK_IMG="ghcr.io/metacubex/mihomo:latest" ;;
                    *adguard/adguardhome*) FALLBACK_IMG="ghcr.io/adguardteam/adguardhome:latest" ;;
                    *amir20/dozzle*) FALLBACK_IMG="ghcr.io/amir20/dozzle:latest" ;;
                    *containrrr/watchtower*) FALLBACK_IMG="ghcr.io/containrrr/watchtower:latest" ;;
                    *willfarrell/autoheal*) FALLBACK_IMG="ghcr.io/willfarrell/autoheal:latest" ;;
                    *servercontainers/samba*) FALLBACK_IMG="ghcr.io/servercontainers/samba:latest" ;;
                    *vaultwarden/server*) FALLBACK_IMG="ghcr.io/dani-garcia/vaultwarden:latest" ;;
                    *gitea/gitea*) FALLBACK_IMG="ghcr.io/go-gitea/gitea:latest" ;;
                esac

                if [ -n "${FALLBACK_IMG}" ]; then
                    log_info "Попытка загрузки через резервный реестр: ${FALLBACK_IMG}..."
                    if docker pull "${FALLBACK_IMG}"; then
                        docker tag "${FALLBACK_IMG}" "${img}" 2>/dev/null || true
                        PULL_DONE=1
                        log_ok "Образ ${img} успешно получен из резервного реестра (${FALLBACK_IMG})"
                    fi
                fi
            fi
        done
    else
        log_info "Режим обновления ядра: повторная загрузка образов пропущена (образы сохранены)"
    fi

    log_info "Запуск контейнеров стека (Docker Compose)..."
    local UP_OK=0
    for up_att in 1 2 3 4; do
        if dc up -d; then
            UP_OK=1
            log_ok "Все контейнеры стека успешно запущены"
            break
        else
            log_warn "Попытка запуска ${up_att}/4 завершилась с ошибкой, повторная попытка через 5 сек..."
            sleep 5
        fi
    done
    if [ $UP_OK -eq 0 ]; then
        log_err "Критическая ошибка запуска контейнеров через Docker Compose!"
        return 1
    fi

    if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
        if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ]; then
            log_ok "Режим обновления: существующий администратор Gitea (${ADMIN_USER}) сохранен"
        else
            log_info "Автоматическая инициализация администратора Gitea (${ADMIN_USER})..."
            local GITEA_READY=0
            for i in {1..40}; do
                if docker inspect -f '{{.State.Status}}' gitea 2>/dev/null | grep -q "running"; then
                    if docker exec gitea wget -q -O - http://localhost:3000/api/v1/version >/dev/null 2>&1 || \
                       docker exec gitea curl -sf http://localhost:3000/api/v1/version >/dev/null 2>&1 || \
                       [ $i -ge 12 ]; then
                        
                        if docker exec -i -e GITEA_ADMIN_PWD="${MASTER_PASS}" -u "${USER_UID}:${USER_GID}" gitea sh -c 'gitea admin user create --config /data/gitea/conf/app.ini --admin --username "$1" --password "$GITEA_ADMIN_PWD" --email "$1@example.lan" --must-change-password=false' _ "${ADMIN_USER}" >/dev/null 2>&1 || \
                           docker exec -i -e GITEA_ADMIN_PWD="${MASTER_PASS}" -u git gitea sh -c 'gitea admin user create --config /data/gitea/conf/app.ini --admin --username "$1" --password "$GITEA_ADMIN_PWD" --email "$1@example.lan" --must-change-password=false' _ "${ADMIN_USER}" >/dev/null 2>&1; then
                            log_ok "Администратор Gitea (${ADMIN_USER}) успешно создан с мастер-паролем"
                            GITEA_READY=1
                        elif docker exec -i -e GITEA_ADMIN_PWD="${MASTER_PASS}" -u git gitea sh -c 'gitea admin user change-password --config /data/gitea/conf/app.ini --username "$1" --password "$GITEA_ADMIN_PWD"' _ "${ADMIN_USER}" >/dev/null 2>&1; then
                            log_ok "Пароль администратора Gitea (${ADMIN_USER}) успешно обновлен на мастер-пароль"
                            GITEA_READY=1
                        fi

                        if [ "${GITEA_READY}" -eq 1 ]; then
                            python3 -c "
import sqlite3, glob, sys
db_paths = glob.glob('${GITEA_DATA_DIR}/**/gitea.db', recursive=True) + glob.glob('${SAVE_DIR}/**/gitea.db', recursive=True)
for p in set(db_paths):
    try:
        conn = sqlite3.connect(p)
        conn.execute('UPDATE user SET must_change_password = 0;')
        conn.commit()
        conn.close()
    except Exception:
        pass
" 2>/dev/null || true
                            break
                        fi
                    fi
                fi
                sleep 2
            done
            [ $GITEA_READY -eq 0 ] && log_warn "Не удалось инициализировать админа Gitea (контейнер запускается в фоновом режиме)"
        fi
    fi

    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        log_ok "Сервис Navidrome готов к работе (порт 4533 / ${MUSIC_DOMAIN})"
        log_info "Создание учетной записи администратора Navidrome выполняется в веб-интерфейсе при первом открытии: https://${MUSIC_DOMAIN}"
    fi

    if [ "$SSL_MODE" = "1" ]; then
        log_info "Экспорт локального корневого сертификата CA Caddy..."
        local CADDY_ROOT_CERT="${APP_DIR}/caddy/data/caddy/pki/authorities/local/root.crt"
        for _ in {1..30}; do
            if [ -f "${CADDY_ROOT_CERT}" ]; then
                mkdir -p "${SAVE_DIR}/certificates"
                cp -f "${CADDY_ROOT_CERT}" "${SAVE_DIR}/certificates/caddy-root.crt"
                chown -R "${USER_UID}:${USER_GID}" "${SAVE_DIR}/certificates" 2>/dev/null || true
                chmod 644 "${SAVE_DIR}/certificates/caddy-root.crt" 2>/dev/null || true
                log_ok "Сертификат CA сохранен: ${SAVE_DIR}/certificates/caddy-root.crt"
                break
            fi
            sleep 1
        done
    fi

    log_info "Установка консольной утилиты управления комплексом (/usr/local/bin/homelab)..."
    local CLI_TMP="/usr/local/bin/homelab.tmp.$$"
    cat << 'EOF_HOMELAB_CLI' > "${CLI_TMP}"
#!/usr/bin/env bash
# =============================================================================
# Homelab Management CLI (Day-2 Operations & SRE Toolkit)
# =============================================================================
set -euo pipefail

APP_DIR="/opt/homelab"
if [ -f "${APP_DIR}/.env" ]; then
    # shellcheck disable=SC1091
    source "${APP_DIR}/.env"
fi
HOMELAB_RAW_URL="https://raw.githubusercontent.com/unknownpeace/Medal/main"

CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_DIM="\033[2m"
CLR_GREEN="\033[1;32m"
CLR_RED="\033[1;31m"
CLR_YELLOW="\033[1;33m"
CLR_CYAN="\033[1;36m"
CLR_WHITE="\033[1;37m"

TAG_OK="${CLR_GREEN}✔${CLR_RESET}"
TAG_ERR="${CLR_RED}✖${CLR_RESET}"
TAG_WARN="${CLR_YELLOW}▲${CLR_RESET}"
TAG_INFO="${CLR_CYAN}✦${CLR_RESET}"

dc_cmd() {
    if [ -x /usr/local/bin/dc ]; then
        /usr/local/bin/dc "$@"
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    elif [ -x /usr/lib/docker/cli-plugins/docker-compose ]; then
        /usr/lib/docker/cli-plugins/docker-compose "$@"
    elif [ -x /usr/libexec/docker/cli-plugins/docker-compose ]; then
        /usr/libexec/docker/cli-plugins/docker-compose "$@"
    else
        docker compose "$@"
    fi
}

norm_service() {
    local s="${1:-}"
    case "$s" in
        adguard|adguardhome) echo "adguardhome" ;;
        vault|vaultwarden) echo "vaultwarden" ;;
        torrent|qbittorrent) echo "qbittorrent" ;;
        music|navidrome) echo "navidrome" ;;
        tube|video|metube) echo "metube" ;;
        git|gitea) echo "gitea" ;;
        proxy|clash|meta|mihomo) echo "mihomo" ;;
        smb|samba) echo "samba" ;;
        caddy|web|proxy-web) echo "caddy" ;;
        logs|dozzle) echo "dozzle" ;;
        autoheal) echo "autoheal" ;;
        watchtower) echo "watchtower" ;;
        *) echo "$s" ;;
    esac
}

cmd_status() {
    echo -e "${CLR_CYAN}${CLR_BOLD}╭── HOMELAB APPLIANCE: СТАТУС СИСТЕМЫ И СЕРВИСОВ ───────────────${CLR_RESET}"
    echo -e "  ${CLR_WHITE}• Версия комплекса:${CLR_RESET}  ${CLR_GREEN}v${SAVED_HOMELAB_VERSION:-2.8.10}${CLR_RESET}"
    echo -e "  ${CLR_WHITE}• Ядро / ОС:${CLR_RESET}         $(uname -srm) [$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || echo 'Linux')]"
    local host_uptime=""
    if [ -r /proc/uptime ]; then
        host_uptime=$(awk '{
            secs=int($1);
            days=int(secs/86400);
            hours=int((secs%86400)/3600);
            mins=int((secs%3600)/60);
            if (days > 0) printf "%d дн. %d ч. %d мин.", days, hours, mins;
            else if (hours > 0) printf "%d ч. %d мин.", hours, mins;
            else printf "%d мин.", mins;
        }' /proc/uptime 2>/dev/null)
    fi
    [ -z "${host_uptime}" ] && host_uptime=$(uptime -p 2>/dev/null || uptime 2>/dev/null | awk '{print $3,$4}' | tr -d ',')
    echo -e "  ${CLR_WHITE}• Аптайм хоста:${CLR_RESET}      ${host_uptime:-N/A}"
    local ram_usage=""
    if [ -r /proc/meminfo ]; then
        ram_usage=$(awk '
            /^MemTotal:/ { total=$2 }
            /^MemAvailable:/ { avail=$2 }
            END {
                used = total - avail;
                printf "%.1fG / %.1fG (%.0f%%)", used/1048576, total/1048576, (used/total)*100
            }
        ' /proc/meminfo 2>/dev/null)
    fi
    [ -z "${ram_usage}" ] && ram_usage=$(free -h 2>/dev/null | awk '/^Mem:/{print $3 " / " $2}')
    local storage_usage=""
    local target_save="${SAVED_SAVE_DIR:-/opt/homelab/save}"
    [ ! -d "${target_save}" ] && target_save="/"
    storage_usage=$(df -h "${target_save}" 2>/dev/null | awk 'NR==2{print $3 " / " $2 " (свободно " $4 ")"}')
    echo -e "  ${CLR_WHITE}• Использование ОЗУ:${CLR_RESET} ${ram_usage:-N/A}"
    echo -e "  ${CLR_WHITE}• Хранилище:${CLR_RESET}         ${storage_usage:-N/A}"
    
    local FW_STATUS="не активен"
    if command -v nft >/dev/null 2>&1 && nft list table inet homelab >/dev/null 2>&1; then
        FW_STATUS="${CLR_GREEN}nftables (таблица inet homelab)${CLR_RESET}"
    fi
    echo -e "  ${CLR_WHITE}• Фаервол / NAT:${CLR_RESET}     ${FW_STATUS}"

    if docker inspect metube >/dev/null 2>&1; then
        local c_file="${target_save}/downloads/.metube/cookies.txt"
        if [ -s "${c_file}" ]; then
            local c_sz
            c_sz=$(ls -lh "${c_file}" 2>/dev/null | awk '{print $5}' || echo "OK")
            echo -e "  ${CLR_WHITE}• YouTube Cookies:${CLR_RESET}   ${CLR_GREEN}🟢 Загружен (${c_sz})${CLR_RESET}"
        else
            echo -e "  ${CLR_WHITE}• YouTube Cookies:${CLR_RESET}   ${CLR_YELLOW}🟡 Не загружен (команда: homelab cookies)${CLR_RESET}"
        fi
    fi
    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
    echo ""

    echo -e "${CLR_CYAN}${CLR_BOLD}╭── СТАТУС КОНТЕЙНЕРОВ DOCKER ─────────────────────────────────${CLR_RESET}"
    printf "  %-18s %-12s %-14s %-10s\n" "СЕРВИС" "СТАТУС" "ЗДОРОВЬЕ" "ПАМЯТЬ"
    echo -e "  ─────────────────────────────────────────────────────────────"
    
    local CONTAINERS=("adguardhome" "mihomo" "caddy" "vaultwarden" "gitea" "qbittorrent" "metube" "navidrome" "samba" "dozzle" "watchtower" "autoheal")
    declare -A DOCKER_MEM
    if command -v docker >/dev/null 2>&1; then
        while read -r d_name d_mem; do
            [ -n "$d_name" ] && DOCKER_MEM["$d_name"]="$d_mem"
        done < <(docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2>/dev/null | awk '{print $1, $2}' || true)
    fi

    for c in "${CONTAINERS[@]}"; do
        if docker inspect "$c" >/dev/null 2>&1; then
            local state
            state=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "stopped")
            local health
            health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo "none")
            local mem="${DOCKER_MEM[$c]:-—}"
            
            local state_str="${CLR_GREEN}Running${CLR_RESET}"
            [ "$state" != "running" ] && state_str="${CLR_RED}${state}${CLR_RESET}"
            
            local health_str="${CLR_DIM}—${CLR_RESET}"
            [ "$health" = "healthy" ] && health_str="${CLR_GREEN}Healthy${CLR_RESET}"
            [ "$health" = "starting" ] && health_str="${CLR_YELLOW}Starting${CLR_RESET}"
            [ "$health" = "unhealthy" ] && health_str="${CLR_RED}UNHEALTHY${CLR_RESET}"
            
            printf "  %-18s %-22b %-24b %-10s\n" "$c" "$state_str" "$health_str" "${mem}"
        fi
    done
    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"

    echo ""
    echo -e "${CLR_CYAN}${CLR_BOLD}╭── АДРЕСА СЕРВИСОВ И ВЕБ-ПОРТАЛОВ ────────────────────────────${CLR_RESET}"
    local BASE_IP="${SAVED_LOCAL_IP:-${LOCAL_IP:-127.0.0.1}}"
    [ -n "${SAVED_MUSIC_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}🎵 Музыка (Navidrome):${CLR_RESET}   https://${SAVED_MUSIC_DOMAIN} (порт 4533)"
    [ -n "${SAVED_METUBE_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}🎬 Загрузчик (MeTube):${CLR_RESET}   https://${SAVED_METUBE_DOMAIN} (порт 8081)"
    [ -n "${SAVED_TORRENT_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}📥 Торренты (qBit):${CLR_RESET}      https://${SAVED_TORRENT_DOMAIN} (порт 8080)"
    [ -n "${SAVED_VAULT_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}🔑 Пароли (Vaultwarden):${CLR_RESET} https://${SAVED_VAULT_DOMAIN}"
    [ -n "${SAVED_GITEA_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}🐙 Git-сервер (Gitea):${CLR_RESET}   https://${SAVED_GITEA_DOMAIN} (порт 3000)"
    [ -n "${SAVED_ADGUARD_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}🛡️  DNS (AdGuard Home):${CLR_RESET}   https://${SAVED_ADGUARD_DOMAIN} (порт 8083)"
    [ -n "${SAVED_PROXY_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}🚀 Прокси (Mihomo UI):${CLR_RESET}   https://${SAVED_PROXY_DOMAIN}"
    [ -n "${SAVED_LOGS_DOMAIN:-}" ] && echo -e "  ${CLR_WHITE}📋 Логи (Dozzle):${CLR_RESET}        https://${SAVED_LOGS_DOMAIN}"
    if docker inspect samba >/dev/null 2>&1; then
        echo -e "  ${CLR_WHITE}📂 Samba Хранилище:${CLR_RESET}      \\\\${BASE_IP}\\${SAVED_SHARE_NAME:-storage} и \\\\${BASE_IP}\\music"
    fi
    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
}

cmd_restart() {
    local target="${1:-}"
    if [ -n "$target" ]; then
        target=$(norm_service "$target")
        shift || true
        echo -e "  ${TAG_INFO} Перезапуск сервиса ${CLR_WHITE}${target}${CLR_RESET}..."
        (cd "$APP_DIR" && dc_cmd restart "$target" "$@")
        echo -e "  ${TAG_OK} Сервис ${target} перезапущен"
    else
        echo -e "  ${TAG_INFO} Перезапуск всего комплекса Homelab..."
        /usr/local/bin/gateway-watchdog.sh 2>/dev/null || true
        (cd "$APP_DIR" && dc_cmd restart)
        echo -e "  ${TAG_OK} Все сервисы успешно перезапущены"
    fi
}

cmd_stop() {
    local target="${1:-}"
    if [ -n "$target" ]; then
        target=$(norm_service "$target")
        shift || true
        echo -e "  ${TAG_INFO} Остановка сервиса ${CLR_WHITE}${target}${CLR_RESET}..."
        (cd "$APP_DIR" && dc_cmd stop "$target" "$@")
        echo -e "  ${TAG_OK} Сервис ${target} остановлен"
    else
        echo -e "  ${TAG_INFO} Остановка всех сервисов Homelab..."
        (cd "$APP_DIR" && dc_cmd stop)
        echo -e "  ${TAG_OK} Все сервисы остановлены"
    fi
}

cmd_start() {
    local target="${1:-}"
    if [ -n "$target" ]; then
        target=$(norm_service "$target")
        shift || true
        echo -e "  ${TAG_INFO} Запуск сервиса ${CLR_WHITE}${target}${CLR_RESET}..."
        (cd "$APP_DIR" && dc_cmd up -d "$target" "$@")
        echo -e "  ${TAG_OK} Сервис ${target} запущен"
    else
        echo -e "  ${TAG_INFO} Запуск всех сервисов Homelab..."
        (cd "$APP_DIR" && dc_cmd up -d)
        echo -e "  ${TAG_OK} Все сервисы запущены"
    fi
}

cmd_logs() {
    local target="${1:-}"
    if [ "$target" = "dump" ] || [ "$target" = "--dump" ] || [ "$target" = "export" ]; then
        shift || true
        cmd_dump_logs "$@"
        return
    fi
    if [ -n "$target" ]; then
        shift || true
        target=$(norm_service "$target")
        (cd "$APP_DIR" && dc_cmd logs "$@" "$target")
    else
        (cd "$APP_DIR" && dc_cmd logs --tail=50 "$@")
    fi
}

cmd_backup() {
    echo -e "  ${TAG_INFO} Запуск резервного копирования баз данных..."
    if [ -x "${APP_DIR}/backup_vaultwarden.sh" ]; then
        echo -e "  ${TAG_INFO} Бэкап Vaultwarden..."
        "${APP_DIR}/backup_vaultwarden.sh"
        echo -e "  ${TAG_OK} Бэкап Vaultwarden завершен"
    fi
    if [ -x "${APP_DIR}/backup_gitea.sh" ]; then
        echo -e "  ${TAG_INFO} Бэкап Gitea..."
        "${APP_DIR}/backup_gitea.sh"
        echo -e "  ${TAG_OK} Бэкап Gitea завершен"
    fi
    if [ -x "${APP_DIR}/backup_navidrome.sh" ]; then
        echo -e "  ${TAG_INFO} Бэкап Navidrome..."
        "${APP_DIR}/backup_navidrome.sh"
        echo -e "  ${TAG_OK} Бэкап Navidrome завершен"
    fi
    echo ""
    echo -e "  ${CLR_CYAN}Файлы бэкапов в хранилище (${SAVED_SAVE_DIR:-/opt/homelab/save}/backups):${CLR_RESET}"
    find "${SAVED_SAVE_DIR:-/opt/homelab/save}/backups" -type f \( -name "*.tar.gz" -o -name "*.zip" -o -name "*.db.gz" -o -name "*.sql.gz" \) 2>/dev/null | while read -r f; do
        printf "    ${CLR_GREEN}•${CLR_RESET} %-45s ${CLR_YELLOW}[%s]${CLR_RESET}\n" "$(basename "$f")" "$(du -h "$f" 2>/dev/null | awk '{print $1}')"
    done
}

cmd_doctor() {
    echo -e "${CLR_CYAN}${CLR_BOLD}╭── HOMELAB DOCTOR: ГЛУБОКАЯ САМОДИАГНОСТИКА ──────────────────${CLR_RESET}"
    
    local ip_fwd
    ip_fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)
    if [ "$ip_fwd" = "1" ]; then
        echo -e "  ${TAG_OK} IPv4 Forwarding ядра:                   ${CLR_GREEN}[АКТИВЕН]${CLR_RESET}"
    else
        echo -e "  ${TAG_ERR} IPv4 Forwarding ядра:                   ${CLR_RED}[ОТКЛЮЧЕН]${CLR_RESET}"
    fi

    if [[ "${SAVED_ENABLE_GATEWAY:-Y}" =~ ^[Yy]$ ]]; then
        if command -v nft >/dev/null 2>&1 && nft list table inet homelab >/dev/null 2>&1; then
            echo -e "  ${TAG_OK} nftables (таблица inet homelab):        ${CLR_GREEN}[АКТИВНА И ПРИМЕНЕНА]${CLR_RESET}"
        else
            echo -e "  ${TAG_ERR} nftables (таблица inet homelab):        ${CLR_RED}[НЕ НАЙДЕНА/ОШИБКА]${CLR_RESET}"
        fi

        if python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2); s.sendto(b'\xaa\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01', ('127.0.0.1', 53)); d, _ = s.recvfrom(512); exit(0 if len(d) > 12 else 1)" 2>/dev/null; then
            echo -e "  ${TAG_OK} DNS Резолвер AdGuard Home (порт 53):    ${CLR_GREEN}[ОТВЕЧАЕТ]${CLR_RESET}"
        else
            echo -e "  ${TAG_ERR} DNS Резолвер AdGuard Home (порт 53):    ${CLR_RED}[НЕ ОТВЕЧАЕТ]${CLR_RESET}"
        fi

        if python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2); s.sendto(b'\xaa\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01', ('127.0.0.1', 1053)); d, _ = s.recvfrom(512); exit(0 if len(d) > 12 else 1)" 2>/dev/null; then
            echo -e "  ${TAG_OK} DNS Ядро Mihomo Fake-IP (порт 1053):    ${CLR_GREEN}[ОТВЕЧАЕТ]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} DNS Ядро Mihomo Fake-IP (порт 1053):    ${CLR_YELLOW}[ОЖИДАНИЕ/ОТКЛЮЧЕН]${CLR_RESET}"
        fi

        if python3 -c "import socket; s = socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 9090)); s.close()" 2>/dev/null; then
            echo -e "  ${TAG_OK} REST API Mihomo (порт 9090):            ${CLR_GREEN}[ОТВЕЧАЕТ]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} REST API Mihomo (порт 9090):            ${CLR_YELLOW}[ОЖИДАНИЕ/ОТКЛЮЧЕН]${CLR_RESET}"
        fi

        if ip link show Meta >/dev/null 2>&1; then
            echo -e "  ${TAG_OK} Сетевой TUN интерфейс ядра (Meta):      ${CLR_GREEN}[АКТИВЕН И ПОДНЯТ]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} Сетевой TUN интерфейс ядра (Meta):      ${CLR_YELLOW}[НЕ СОЗДАН/ОЖИДАНИЕ]${CLR_RESET}"
        fi
    else
        echo -e "  ${TAG_INFO} Сетевой шлюз (AdGuard + Mihomo):       ${CLR_DIM}[ОТКЛЮЧЕН В КОНФИГУРАЦИИ]${CLR_RESET}"
    fi

    if [ -c /dev/net/tun ]; then
        echo -e "  ${TAG_OK} Виртуальное устройство TUN (/dev/net/tun): ${CLR_GREEN}[ДОСТУПНО]${CLR_RESET}"
    else
        echo -e "  ${TAG_ERR} Виртуальное устройство TUN (/dev/net/tun): ${CLR_RED}[ОТСУТСТВУЕТ]${CLR_RESET}"
    fi

    if [ -w "${SAVED_SAVE_DIR:-/opt/homelab/save}" ]; then
        echo -e "  ${TAG_OK} Каталог данных хранилища:               ${CLR_GREEN}[ДОСТУПЕН ДЛЯ ЗАПИСИ]${CLR_RESET}"
    else
        echo -e "  ${TAG_ERR} Каталог данных хранилища:               ${CLR_RED}[ОШИБКА ПРАВ ДОСТУПА]${CLR_RESET}"
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -sk -m 2 http://127.0.0.1:80/ >/dev/null 2>&1 || curl -sk -m 2 https://127.0.0.1:443/ >/dev/null 2>&1; then
            echo -e "  ${TAG_OK} Caddy Reverse Proxy (HTTP 80/443):      ${CLR_GREEN}[ОТВЕЧАЕТ]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} Caddy Reverse Proxy (HTTP 80/443):      ${CLR_YELLOW}[ОЖИДАНИЕ ТРАФИКА]${CLR_RESET}"
        fi
    fi

    if [[ "${SAVED_ENABLE_GATEWAY:-Y}" =~ ^[Yy]$ ]]; then
        if command -v nft >/dev/null 2>&1 && nft list table inet homelab 2>/dev/null | grep -E -q 'dport 53 redirect|redirect to :?53'; then
            echo -e "  ${TAG_OK} Перехват DNS в LAN (DNS Hijack):         ${CLR_GREEN}[АКТИВЕН (порт 53 -> AdGuard)]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} Перехват DNS в LAN (DNS Hijack):         ${CLR_YELLOW}[НЕ НАСТРОЕН]${CLR_RESET}"
        fi

        if command -v nft >/dev/null 2>&1 && nft list table inet homelab 2>/dev/null | grep -E -q 'maxseg|tcp option maxseg'; then
            echo -e "  ${TAG_OK} Оптимизация MTU (TCP MSS Clamping):      ${CLR_GREEN}[АКТИВНА (защита от дропов)]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} Оптимизация MTU (TCP MSS Clamping):      ${CLR_YELLOW}[НЕ НАСТРОЕНА]${CLR_RESET}"
        fi

        if [ -f /opt/homelab/mihomo/config.yaml ] && grep -q 'my-sub' /opt/homelab/mihomo/config.yaml 2>/dev/null; then
            echo -e "  ${TAG_OK} Прокси-подписка (VLESS/Trojan/SS):        ${CLR_GREEN}[АКТИВНА (my-sub -> AUTO/PROXY)]${CLR_RESET}"
        fi

        if command -v nft >/dev/null 2>&1 && nft list table inet homelab 2>/dev/null | grep -E -q 'priority.*- ?10|hook forward'; then
            echo -e "  ${TAG_OK} Пересылка трафика LAN/TUN (nftables FORWARD): ${CLR_GREEN}[АКТИВНА (priority -10)]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} Пересылка трафика LAN/TUN (nftables FORWARD): ${CLR_YELLOW}[ПРОВЕРЬТЕ NFTABLES]${CLR_RESET}"
        fi

        if [ -f /opt/homelab/mihomo/config.yaml ] && grep -q 'connectivitycheck' /opt/homelab/mihomo/config.yaml 2>/dev/null; then
            echo -e "  ${TAG_OK} Доступность сети Android (Captive Portal 204):   ${CLR_GREEN}[АКТИВНА (DIRECT)]${CLR_RESET}"
        fi

        if [ -f /opt/homelab/adguard/conf/AdGuardHome.yaml ] && grep -E -q 'cache_enabled: false|cache_size: 0' /opt/homelab/adguard/conf/AdGuardHome.yaml 2>/dev/null; then
            echo -e "  ${TAG_OK} Синхронизация Fake-IP (AdGuard Cache Off):   ${CLR_GREEN}[АКТИВНА (кэш отключен, нет рассинхрона)]${CLR_RESET}"
        fi

        if [ -f /opt/homelab/adguard/conf/AdGuardHome.yaml ] && grep -q 'anonymize_client_ip: false' /opt/homelab/adguard/conf/AdGuardHome.yaml 2>/dev/null; then
            echo -e "  ${TAG_OK} Идентификация клиентов LAN (AdGuard):     ${CLR_GREEN}[АКТИВНА (полные IP и имена устройств)]${CLR_RESET}"
        fi
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^metube$'; then
        echo -e "  ${TAG_OK} Видео-загрузчик MeTube:                     ${CLR_GREEN}[АКТИВЕН (порт 8081)]${CLR_RESET}"
    fi

    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
}

cmd_update() {
    echo -e "  ${TAG_INFO} Проверка и загрузка свежих версий Docker-образов..."
    if ! (cd "$APP_DIR" && dc_cmd pull); then
        echo -e "  ${TAG_WARN} Штатный dc pull завершился со сбоем. Загрузка через российские зеркала и fallback..."
        local IMAGES=()
        if (cd "$APP_DIR" && dc_cmd config --images >/dev/null 2>&1); then
            while IFS= read -r line; do
                [ -n "$line" ] && IMAGES+=("$line")
            done < <(cd "$APP_DIR" && dc_cmd config --images 2>/dev/null | sort -u)
        fi
        for img in "${IMAGES[@]}"; do
            local PREFIX_IMG="${img}"
            [[ ! "${PREFIX_IMG}" =~ / ]] && PREFIX_IMG="library/${PREFIX_IMG}"
            for mirror in "dockerhub.timeweb.cloud" "dockerproxy.net" "docker.m.daocloud.io"; do
                if docker pull "${mirror}/${PREFIX_IMG}"; then
                    docker tag "${mirror}/${PREFIX_IMG}" "${img}" 2>/dev/null || true
                    docker rmi "${mirror}/${PREFIX_IMG}" >/dev/null 2>&1 || true
                    break
                fi
            done
        done
    fi
    echo -e "  ${TAG_INFO} Пересоздание контейнеров с новыми образами..."
    (cd "$APP_DIR" && dc_cmd up -d --remove-orphans)
    echo -e "  ${TAG_INFO} Очистка неиспользуемых устаревших слоёв..."
    docker image prune -f >/dev/null 2>&1 || true
    echo -e "  ${TAG_OK} Стек Homelab успешно обновлен до последних версий!"
}

cmd_version() {
    echo -e "${CLR_CYAN}${CLR_BOLD}╭── ВЕРСИЯ И СТАТУС ОБНОВЛЕНИЙ HOMELAB ───────────────────────${CLR_RESET}"
    local CUR_VER="${SAVED_HOMELAB_VERSION:-2.8.13}"
    echo -e "  ${TAG_INFO} Установленная версия ядра:   ${CLR_GREEN}v${CUR_VER}${CLR_RESET}"

    local REMOTE_VER=""
    if command -v curl >/dev/null 2>&1; then
        REMOTE_VER=$(curl -fsSL -m 4 "${HOMELAB_RAW_URL}/VERSION" 2>/dev/null | tr -d ' \r\n' || true)
    elif command -v wget >/dev/null 2>&1; then
        REMOTE_VER=$(wget -qO- --timeout=4 "${HOMELAB_RAW_URL}/VERSION" 2>/dev/null | tr -d ' \r\n' || true)
    fi

    if [ -n "${REMOTE_VER}" ]; then
        echo -e "  ${TAG_INFO} Последняя версия на GitHub:  ${CLR_WHITE}v${REMOTE_VER}${CLR_RESET}"
        if [ "${REMOTE_VER}" != "${CUR_VER}" ]; then
            echo ""
            echo -e "  ${CLR_YELLOW}⚡ ДОСТУПНО ОБНОВЛЕНИЕ!${CLR_RESET} Вы можете обновить комплекс без потери данных:"
            echo -e "      ${CLR_GREEN}homelab upgrade${CLR_RESET}"
        else
            echo -e "  ${TAG_OK} У вас установлена самая актуальная версия комплекса."
        fi
    else
        echo -e "  ${TAG_WARN} Не удалось проверить последнюю версию (нет связи с GitHub)"
    fi
    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
}

cmd_upgrade() {
    local FORCE=0
    for a in "$@"; do
        if [ "$a" = "--force" ] || [ "$a" = "-f" ]; then
            FORCE=1
        fi
    done

    echo -e "${CLR_CYAN}${CLR_BOLD}╭── БЕСШОВНОЕ ОБНОВЛЕНИЕ КОМПЛЕКСА (IN-PLACE OTA UPGRADE) ─────${CLR_RESET}"
    local CUR_VER="${SAVED_HOMELAB_VERSION:-2.8.13}"
    echo -e "  ${TAG_INFO} Текущая установленная версия: ${CLR_GREEN}v${CUR_VER}${CLR_RESET}"
    echo -e "  ${TAG_INFO} Проверка доступности свежего релиза на GitHub..."

    local REMOTE_VER=""
    if command -v curl >/dev/null 2>&1; then
        REMOTE_VER=$(curl -fsSL -m 5 "${HOMELAB_RAW_URL}/VERSION" 2>/dev/null | tr -d ' \r\n' || true)
    elif command -v wget >/dev/null 2>&1; then
        REMOTE_VER=$(wget -qO- --timeout=5 "${HOMELAB_RAW_URL}/VERSION" 2>/dev/null | tr -d ' \r\n' || true)
    fi

    if [ -z "${REMOTE_VER}" ]; then
        echo -e "  ${TAG_WARN} Не удалось получить информацию о версии с GitHub."
        if [ $FORCE -eq 0 ]; then
            echo -e "  Для принудительного обновления выполните: ${CLR_GREEN}homelab upgrade --force${CLR_RESET}"
            echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
            return 1
        fi
        REMOTE_VER="latest"
    fi

    if [ "${REMOTE_VER}" = "${CUR_VER}" ] && [ $FORCE -eq 0 ]; then
        echo -e "  ${TAG_OK} У вас уже установлена актуальная версия ${CLR_WHITE}v${CUR_VER}${CLR_RESET}."
        echo -e "  Для принудительной переустановки: ${CLR_GREEN}homelab upgrade --force${CLR_RESET}"
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        return 0
    fi

    echo -e "  ${CLR_YELLOW}⚡ Обновление: v${CUR_VER} ➔ v${REMOTE_VER}${CLR_RESET}"
    echo -e "  ${TAG_INFO} [1/4] Создание снимка восстановления (Pre-Upgrade Snapshot)..."
    local SNAPSHOT_DIR="${APP_DIR}/backups/snapshots"
    mkdir -p "${SNAPSHOT_DIR}"
    local SNAP_TAR="${SNAPSHOT_DIR}/homelab_snapshot_pre_upgrade.tar.gz"

    local SNAP_FILES=(".env")
    [ -f "${APP_DIR}/docker-compose.yml" ] && SNAP_FILES+=("docker-compose.yml") || true
    [ -f "${APP_DIR}/Caddyfile" ] && SNAP_FILES+=("Caddyfile") || true
    [ -d "${APP_DIR}/caddy" ] && SNAP_FILES+=("caddy") || true
    [ -f "${APP_DIR}/mihomo/config.yaml" ] && SNAP_FILES+=("mihomo/config.yaml") || true
    [ -f "${APP_DIR}/adguard/conf/AdGuardHome.yaml" ] && SNAP_FILES+=("adguard/conf/AdGuardHome.yaml") || true
    [ -d "${APP_DIR}/configs/navidrome" ] && SNAP_FILES+=("configs/navidrome") || true

    tar -czf "${SNAP_TAR}" -C "${APP_DIR}" "${SNAP_FILES[@]}" 2>/dev/null || tar -czf "${SNAP_TAR}" -C "${APP_DIR}" .env 2>/dev/null || true
    chmod 600 "${SNAP_TAR}" 2>/dev/null || true
    echo -e "  ${TAG_OK} Снимок конфигураций сохранен в: ${SNAP_TAR}"

    echo -e "  ${TAG_INFO} [2/4] Загрузка нового установщика с GitHub..."
    local TMP_UPGRADE="/tmp/homelab_upgrade_installer.sh"
    rm -f "${TMP_UPGRADE}"

    local DL_OK=0
    if curl -fsSL -m 40 "${HOMELAB_RAW_URL}/install.sh" -o "${TMP_UPGRADE}" 2>/dev/null; then
        DL_OK=1
    elif command -v wget >/dev/null 2>&1 && wget -q --timeout=40 "${HOMELAB_RAW_URL}/install.sh" -O "${TMP_UPGRADE}" 2>/dev/null; then
        DL_OK=1
    fi

    if [ $DL_OK -eq 0 ] || [ ! -s "${TMP_UPGRADE}" ]; then
        echo -e "  ${TAG_ERR} Сбой загрузки пакета обновления. Текущий сервер не изменен."
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        return 1
    fi

    echo -e "  ${TAG_INFO} [3/4] Проверка синтаксиса и целостности скрипта..."
    if ! bash -n "${TMP_UPGRADE}" >/dev/null 2>&1; then
        echo -e "  ${TAG_ERR} Обнаружена синтаксическая ошибка в коде обновления! Откат."
        rm -f "${TMP_UPGRADE}"
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        return 1
    fi
    chmod +x "${TMP_UPGRADE}"

    echo -e "  ${TAG_INFO} [4/4] Бесшовный накат обновления (In-Place Upgrade)..."
    if bash "${TMP_UPGRADE}" --upgrade; then
        rm -f "${TMP_UPGRADE}"
        echo ""
        echo -e "  ${CLR_GREEN}${CLR_BOLD}✔  КОМПЛЕКС УСПЕШНО ОБНОВЛЕН ДО v${REMOTE_VER}!${CLR_RESET}"
        echo -e "  Все пользовательские данные, базы и учетные записи сохранены."
        echo -e "  В случае необходимости отката: ${CLR_GREEN}homelab rollback${CLR_RESET}"
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        exit 0
    else
        echo -e "  ${TAG_ERR} В процессе обновления произошла ошибка!"
        echo -e "  Для отката к исходному состоянию выполните: ${CLR_GREEN}homelab rollback${CLR_RESET}"
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        exit 1
    fi
}

cmd_rollback() {
    local SNAP_TAR="${APP_DIR}/backups/snapshots/homelab_snapshot_pre_upgrade.tar.gz"
    echo -e "${CLR_CYAN}${CLR_BOLD}╭── ОТКАТ К ПРЕДЫДУЩЕЙ ВЕРСИИ (ROLLBACK SNAPSHOT) ────────────${CLR_RESET}"
    if [ ! -f "${SNAP_TAR}" ]; then
        echo -e "  ${TAG_ERR} Снимок восстановления не найден: ${SNAP_TAR}"
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        return 1
    fi

    echo -e "  ${TAG_INFO} Восстановление конфигураций из снимка..."
    tar -xzf "${SNAP_TAR}" -C "${APP_DIR}" 2>/dev/null || true

    echo -e "  ${TAG_INFO} Перезапуск сервисов после отката..."
    (cd "${APP_DIR}" && dc_cmd up -d) >/dev/null 2>&1 || true

    echo -e "  ${TAG_OK} Откат завершен: конфигурация успешно возвращена к предыдущему состоянию."
    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
}

cmd_notify() {
    local msg="${1:-Тестовое уведомление из консоли Homelab CLI}"
    echo -e "  ${TAG_INFO} Отправка уведомления в Telegram..."
    if /usr/local/bin/homelab-notify "Тест Homelab CLI" "$msg" "INFO"; then
        echo -e "  ${TAG_OK} Команда отправки выполнена"
    else
        echo -e "  ${TAG_ERR} Сбой отправки (проверьте параметры Telegram в /opt/homelab/.env)"
    fi
}

cmd_cookies() {
    local target_save="${SAVED_SAVE_DIR:-/opt/homelab/save}"
    local cookie_dir="${target_save}/downloads/.metube"
    local cookie_file="${cookie_dir}/cookies.txt"
    local ytdl_conf="${cookie_dir}/ytdl_options.json"
    mkdir -p "${cookie_dir}"

    local arg="${1:-}"

    if [ -z "$arg" ]; then
        echo -e "${CLR_CYAN}${CLR_BOLD}╭── УПРАВЛЕНИЕ YOUTUBE COOKIES ДЛЯ METUBE ────────────────────${CLR_RESET}"
        if [ -s "${cookie_file}" ]; then
            local c_size c_date
            c_size=$(ls -lh "${cookie_file}" 2>/dev/null | awk '{print $5}' || echo "N/A")
            c_date=$(date -r "${cookie_file}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "N/A")
            echo -e "  ${TAG_OK} YouTube Cookies: ${CLR_GREEN}[АКТИВЕН]${CLR_RESET}"
            echo -e "      • Размер файла:   ${CLR_WHITE}${c_size}${CLR_RESET}"
            echo -e "      • Дата изменения: ${CLR_WHITE}${c_date}${CLR_RESET}"
            echo -e "      • Путь на диске:  ${CLR_WHITE}${cookie_file}${CLR_RESET}"
            echo ""
            echo -e "  ${TAG_INFO} Для обновления файла cookies выполните:"
            echo -e "      ${CLR_GREEN}homelab cookies /путь/к/cookies.txt${CLR_RESET}"
            echo -e "      или вставьте из буфера: ${CLR_GREEN}homelab cookies --paste${CLR_RESET}"
            echo -e "      или скопируйте через Samba: ${CLR_WHITE}\\\\${SAVED_LOCAL_IP:-IP}\\${SAVED_SHARE_NAME:-storage}\\downloads\\.metube\\cookies.txt${CLR_RESET}"
            echo -e "  ${TAG_INFO} Для удаления cookies: ${CLR_YELLOW}homelab cookies clear${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} YouTube Cookies: ${CLR_YELLOW}[НЕ ЗАГРУЖЕН]${CLR_RESET}"
            echo -e "  ${CLR_WHITE}Файл cookies необходим для скачивания приватных видео, плейлистов${CLR_RESET}"
            echo -e "  ${CLR_WHITE}и обхода блокировок YouTube (\"Sign in to confirm you're not a bot\").${CLR_RESET}"
            echo ""
            echo -e "  ${TAG_INFO} Способы установки cookies:"
            echo -e "    1) Указать файл на сервере:  ${CLR_GREEN}homelab cookies /путь/к/cookies.txt${CLR_RESET}"
            echo -e "    2) Вставить текст из буфера: ${CLR_GREEN}homelab cookies --paste${CLR_RESET}"
            echo -e "    3) Поместить через Samba в:  ${CLR_WHITE}\\\\${SAVED_LOCAL_IP:-IP}\\${SAVED_SHARE_NAME:-storage}\\downloads\\.metube\\cookies.txt${CLR_RESET}"
        fi
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        return 0
    fi

    if [ "$arg" = "clear" ] || [ "$arg" = "remove" ] || [ "$arg" = "delete" ] || [ "$arg" = "rm" ]; then
        rm -f "${cookie_file}"
        echo '{}' > "${ytdl_conf}"
        chown -R "${SAVED_TARGET_USER:-homelab}:${SAVED_TARGET_USER:-homelab}" "${cookie_dir}" 2>/dev/null || true
        echo -e "  ${TAG_OK} Файл cookies.txt удален, параметры yt-dlp сброшены"
        if docker inspect metube >/dev/null 2>&1; then
            docker restart metube >/dev/null 2>&1 || true
            echo -e "  ${TAG_OK} Контейнер MeTube перезапущен"
        fi
        return 0
    fi

    if [ "$arg" = "--paste" ] || [ "$arg" = "-p" ]; then
        echo -e "${CLR_CYAN}${CLR_BOLD}╭── ВСТАВКА СОДЕРЖИМОГО COOKIES.TXT ──────────────────────────${CLR_RESET}"
        echo -e "  ${CLR_WHITE}Вставьте содержимое файла cookies (Netscape format) и нажмите Enter, затем Ctrl+D:${CLR_RESET}"
        local tmp_c="${cookie_file}.tmp.$$"
        cat > "${tmp_c}"
        if [ -s "${tmp_c}" ]; then
            mv -f "${tmp_c}" "${cookie_file}"
            echo '{"cookiefile": "/downloads/.metube/cookies.txt"}' > "${ytdl_conf}"
            chown -R "${SAVED_TARGET_USER:-homelab}:${SAVED_TARGET_USER:-homelab}" "${cookie_dir}" 2>/dev/null || true
            chmod 600 "${cookie_file}" 2>/dev/null || true
            echo -e "  ${TAG_OK} Файл cookies.txt успешно сохранен (${cookie_file})"
            if docker inspect metube >/dev/null 2>&1; then
                echo -e "  ${TAG_INFO} Перезапуск MeTube для применения cookies..."
                docker restart metube >/dev/null 2>&1 || true
                echo -e "  ${TAG_OK} Контейнер MeTube успешно перезапущен"
            fi
        else
            rm -f "${tmp_c}"
            echo -e "  ${TAG_ERR} Пустой ввод. Изменения не сохранены."
        fi
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        return 0
    fi

    if [ -f "$arg" ]; then
        cp -f "$arg" "${cookie_file}"
        echo '{"cookiefile": "/downloads/.metube/cookies.txt"}' > "${ytdl_conf}"
        chown -R "${SAVED_TARGET_USER:-homelab}:${SAVED_TARGET_USER:-homelab}" "${cookie_dir}" 2>/dev/null || true
        chmod 600 "${cookie_file}" 2>/dev/null || true
        echo -e "  ${TAG_OK} Cookies успешно установлены из: ${arg}"
        if docker inspect metube >/dev/null 2>&1; then
            echo -e "  ${TAG_INFO} Перезапуск MeTube для применения cookies..."
            docker restart metube >/dev/null 2>&1 || true
            echo -e "  ${TAG_OK} Контейнер MeTube успешно перезапущен"
        fi
        return 0
    else
        echo -e "  ${TAG_ERR} Указанный файл не найден: ${arg}"
        return 1
    fi
}

cmd_dump_logs() {
    local out_file="${1:-/opt/homelab/homelab_logs.txt}"
    local user_file="/home/${SAVED_TARGET_USER:-homelab}/homelab_logs.txt"
    [ ! -d "/home/${SAVED_TARGET_USER:-homelab}" ] && user_file="/root/homelab_logs.txt"
    local lines="${2:-200}"

    echo -e "${CLR_CYAN}${CLR_BOLD}╭── СБОР ДИАГНОСТИЧЕСКИХ ЛОГОВ HOMELAB ─────────────────────────${CLR_RESET}"
    echo -e "  ${TAG_INFO} Сбор данных системы, сети и журналов Docker (по ${lines} строк)..."

    {
        echo "============================================================================="
        echo "         HOMELAB APPLIANCE & GATEWAY: ДИАГНОСТИЧЕСКИЙ ДАМП ЛОГОВ             "
        echo "                 Дата и время: $(date '+%Y-%m-%d %H:%M:%S %Z')              "
        echo "============================================================================="
        echo "Хост:            $(hostname 2>/dev/null || uname -n)"
        echo "Ядро / ОС:       $(uname -srm) [$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || echo 'Linux')]"
        echo "Аптайм:          $(uptime 2>/dev/null || true)"
        echo "ОЗУ:             $(free -h 2>/dev/null || true)"
        echo "Хранилище:       $(df -h 2>/dev/null || true)"
        echo "IP адреса:       $(ip -o -4 addr show 2>/dev/null || ifconfig 2>/dev/null || true)"
        echo "Маршруты (main): $(ip route show 2>/dev/null || route -n 2>/dev/null || true)"
        echo "Правила routing policy (ip rule):"
        ip rule show 2>/dev/null || true
        echo "Маршруты (все таблицы):"
        ip route show table all 2>/dev/null || true
        echo ""
        echo "--- СТАТУС КОНТЕЙНЕРОВ DOCKER ---"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
        echo ""
        echo "--- РЕЗУЛЬТАТЫ САМОДИАГНОСТИКИ (HOMELAB DOCTOR) ---"
        cmd_doctor 2>&1 || true
        echo ""
        echo "--- ПРАВИЛА ФАЕРВОЛА (NFTABLES) ---"
        if command -v nft >/dev/null 2>&1; then
            nft list table inet homelab 2>/dev/null || nft list ruleset 2>/dev/null || echo "nftables: нет активных правил"
        else
            echo "nftables: утилита nft не найдена"
        fi
        echo ""
        echo "============================================================================="
        echo "                         ЖУРНАЛЫ КОНТЕЙНЕРОВ DOCKER                          "
        echo "============================================================================="

        local ALL_CONTAINERS=("adguardhome" "mihomo" "caddy" "dozzle" "watchtower" "autoheal" "vaultwarden" "gitea" "qbittorrent" "metube" "navidrome" "samba")
        for c in "${ALL_CONTAINERS[@]}"; do
            if docker inspect "$c" >/dev/null 2>&1; then
                local st
                st=$(docker inspect -f '{{.State.Status}} (Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}})' "$c" 2>/dev/null || echo "unknown")
                echo ""
                echo "-----------------------------------------------------------------------------"
                echo ">>> СЕРВИС: ${c} [Статус: ${st}] (последние ${lines} строк):"
                echo "-----------------------------------------------------------------------------"
                docker logs --tail "${lines}" "$c" 2>&1 || echo "Не удалось получить логи для ${c}"
            fi
        done

        echo ""
        echo "============================================================================="
        echo "                  ЖУРНАЛЫ СТОРОЖЕВОГО ТАЙМЕРА (WATCHDOG)                    "
        echo "============================================================================="
        if [ -f /var/log/messages ]; then
            grep -E 'gateway-watchdog|homelab' /var/log/messages 2>/dev/null | tail -n 50 || echo "Записей watchdog в syslog не обнаружено"
        elif command -v journalctl >/dev/null 2>&1; then
            journalctl -u network-gateway-watchdog.service -n 50 --no-pager 2>/dev/null || echo "Записей watchdog в journald не обнаружено"
        fi


        echo ""
        echo "============================================================================="
        echo "                            КОНЕЦ ДИАГНОСТИКИ                                "
        echo "============================================================================="
    } > "${out_file}" 2>&1

    if [ "${out_file}" != "${user_file}" ]; then
        cp -f "${out_file}" "${user_file}" 2>/dev/null || true
        chmod 644 "${user_file}" 2>/dev/null || true
        chown "${SAVED_TARGET_USER:-root}:" "${user_file}" 2>/dev/null || true
    fi
    chmod 644 "${out_file}" 2>/dev/null || true

    local file_size
    file_size=$(du -h "${out_file}" 2>/dev/null | awk '{print $1}' || echo "N/A")

    echo -e "  ${TAG_OK} Все логи и диагностика успешно сохранены (${file_size}):"
    echo -e "      • ${CLR_WHITE}${out_file}${CLR_RESET}"
    if [ -f "${user_file}" ] && [ "${out_file}" != "${user_file}" ]; then
        echo -e "      • ${CLR_WHITE}${user_file}${CLR_RESET}"
    fi
    echo ""
    echo -e "  ${TAG_INFO} Чтобы просмотреть или скопировать вывод, выполните:"
    echo -e "      ${CLR_GREEN}cat ${out_file}${CLR_RESET}"
    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
}

cmd_help() {
    echo -e "${CLR_CYAN}${CLR_BOLD}Утилита управления комплексом Homelab & Transparent Gateway${CLR_RESET}"
    echo ""
    echo -e "Использование: ${CLR_GREEN}homelab [КОМАНДА] [ОПЦИИ]${CLR_RESET}"
    echo ""
    echo -e "Команды:"
    echo -e "  ${CLR_WHITE}status${CLR_RESET}              Вывести дашборд состояния системы и контейнеров"
    echo -e "  ${CLR_WHITE}restart [сервис]${CLR_RESET}    Перезапустить весь стек или отдельный сервис"
    echo -e "  ${CLR_WHITE}stop [сервис]${CLR_RESET}       Остановить весь стек или сервис"
    echo -e "  ${CLR_WHITE}start [сервис]${CLR_RESET}      Запустить сервисы стека"
    echo -e "  ${CLR_WHITE}logs [сервис] [-f]${CLR_RESET}  Просмотр журналов логов (с ключом -f для реалтайма)"
    echo -e "  ${CLR_WHITE}dump-logs [файл]${CLR_RESET}    Собрать логи всех сервисов и системы в единый файл"
    echo -e "  ${CLR_WHITE}doctor${CLR_RESET}              Комплексная самодиагностика DNS, TUN, NAT и прав"
    echo -e "  ${CLR_WHITE}backup${CLR_RESET}              Запуск горячего бэкапа баз данных прямо сейчас"
    echo -e "  ${CLR_WHITE}notify [текст]${CLR_RESET}      Отправить тестовое оповещение в Telegram"
    echo -e "  ${CLR_WHITE}cookies [файл|--paste|clear]${CLR_RESET} Управление cookies YouTube для MeTube (yt-dlp)"
    echo -e "  ${CLR_WHITE}update${CLR_RESET}              Обновление всех Docker-образов стека"
    echo -e "  ${CLR_WHITE}upgrade [--force]${CLR_RESET}   Бесшовный апгрейд ядра комплекса из GitHub (OTA)"
    echo -e "  ${CLR_WHITE}rollback${CLR_RESET}            Откат к предыдущей версии из снимка восстановления"
    echo -e "  ${CLR_WHITE}version${CLR_RESET}             Проверить установленную версию и обновления на GitHub"
    echo -e "  ${CLR_WHITE}unlock${CLR_RESET}              Ручная разблокировка шифрованного диска LUKS"
    echo -e "  ${CLR_WHITE}help${CLR_RESET}                Показать эту справку"
    echo ""
}

case "${1:-status}" in
    status) cmd_status ;;
    restart) shift; cmd_restart "$@" ;;
    stop) shift; cmd_stop "$@" ;;
    start) shift; cmd_start "$@" ;;
    logs) shift; cmd_logs "$@" ;;
    dump|dump-logs|export-logs|collect|report) shift; cmd_dump_logs "$@" ;;
    backup) cmd_backup ;;
    doctor|check) cmd_doctor ;;
    cookies|cookie) shift; cmd_cookies "$@" ;;
    upgrade|self-update|ota) shift; cmd_upgrade "$@" ;;
    rollback|revert) cmd_rollback ;;
    version|-v|--version|check-update) cmd_version ;;
    notify|test-notify) shift; cmd_notify "$@" ;;
    update) cmd_update ;;
    unlock)
        if [ -x /usr/local/bin/homelab-unlock ]; then
            /usr/local/bin/homelab-unlock
        else
            echo "[-] Шифрование LUKS2 не настроено в данной конфигурации."
        fi
        ;;
    help|--help|-h) cmd_help ;;
    *) cmd_help ;;
esac
EOF_HOMELAB_CLI
    chmod 755 "${CLI_TMP}"
    mv -f "${CLI_TMP}" /usr/local/bin/homelab

    local MIHOMO_TMP="/usr/local/bin/mihomo.tmp.$$"
    cat << 'EOF_MIHOMO_BIN' > "${MIHOMO_TMP}"
#!/usr/bin/env bash
if [ $# -eq 0 ]; then
    echo -e "\033[1;36m✦ Mihomo (Clash Meta) запущен в контейнере Docker.\033[0m"
    echo "  Просмотр логов:       homelab logs mihomo -f"
    echo "  Перезапуск сервиса:   homelab restart mihomo"
    echo "  Консоль контейнера:   docker exec -it mihomo sh"
    echo "  Веб-интерфейс:        https://proxy.lan"
else
    exec docker exec -it mihomo "$@"
fi
EOF_MIHOMO_BIN
    chmod 755 "${MIHOMO_TMP}" 2>/dev/null || true
    mv -f "${MIHOMO_TMP}" /usr/local/bin/mihomo 2>/dev/null || true

    local ADGUARD_TMP="/usr/local/bin/adguard.tmp.$$"
    cat << 'EOF_ADGUARD_BIN' > "${ADGUARD_TMP}"
#!/usr/bin/env bash
if [ $# -eq 0 ]; then
    echo -e "\033[1;36m✦ AdGuard Home запущен в контейнере Docker.\033[0m"
    echo "  Просмотр логов:       homelab logs adguardhome -f"
    echo "  Перезапуск сервиса:   homelab restart adguardhome"
    echo "  Консоль контейнера:   docker exec -it adguardhome sh"
    echo "  Веб-интерфейс:        https://adguard.lan"
else
    exec docker exec -it adguardhome "$@"
fi
EOF_ADGUARD_BIN
    chmod 755 "${ADGUARD_TMP}" 2>/dev/null || true
    mv -f "${ADGUARD_TMP}" /usr/local/bin/adguard 2>/dev/null || true
    ln -sf /usr/local/bin/adguard /usr/local/bin/adguardhome 2>/dev/null || true

    log_ok "Сервисы комплекса успешно запущены и готовы к работе"
    log_ok "Службы автозапуска и горячего резервного копирования активированы"
}
