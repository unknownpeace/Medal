# =============================================================================
# Module: 04_config.sh
# Interactive Configuration Wizard (Express / Custom / Reset) & Password Hashes
# =============================================================================

save_configuration() {
    mkdir -p "${APP_DIR}"
    {
        printf "SAVED_PHYS_IFACE=%q\n" "${DEFAULT_IFACE}"
        printf "SAVED_LOCAL_IP=%q\n" "${LOCAL_IP}"
        printf "SAVED_ROUTER_GATEWAY=%q\n" "${ROUTER_GATEWAY}"
        printf "SAVED_LAN_SUBNET=%q\n" "${LAN_SUBNET}"
        printf "SAVED_ENABLE_GATEWAY=%q\n" "${ENABLE_GATEWAY}"
        printf "SAVED_ENABLE_VAULT=%q\n" "${ENABLE_VAULT}"
        printf "SAVED_ENABLE_GITEA=%q\n" "${ENABLE_GITEA}"
        printf "SAVED_ENABLE_SAMBA=%q\n" "${ENABLE_SAMBA}"
        printf "SAVED_ENABLE_QBIT=%q\n" "${ENABLE_QBIT}"
        printf "SAVED_ENABLE_METUBE=%q\n" "${ENABLE_METUBE}"
        printf "SAVED_METUBE_DOMAIN=%q\n" "${METUBE_DOMAIN}"
        printf "SAVED_ENABLE_NAVIDROME=%q\n" "${ENABLE_NAVIDROME}"
        printf "SAVED_MUSIC_DOMAIN=%q\n" "${MUSIC_DOMAIN}"
        printf "SAVED_SSL_MODE=%q\n" "${SSL_MODE}"
        printf "SAVED_DUCKDNS_NAME=%q\n" "${DUCKDNS_NAME}"
        printf "SAVED_DUCKDNS_TOKEN=%q\n" "${DUCKDNS_TOKEN}"
        printf "SAVED_SUB_URL=%q\n" "${SUB_URL}"
        printf "SAVED_TARGET_USER=%q\n" "${TARGET_USER}"
        printf "SAVED_ADMIN_USER=%q\n" "${ADMIN_USER}"
        printf "SAVED_MASTER_PASS=%q\n" "${MASTER_PASS}"
        printf "SAVED_MIHOMO_SECRET=%q\n" "${MIHOMO_SECRET}"
        printf "SAVED_VAULT_ADMIN_TOKEN=%q\n" "${VAULT_ADMIN_TOKEN}"
        printf "SAVED_STORAGE_MODE=%q\n" "${STORAGE_MODE}"
        printf "SAVED_SUBDIR_NAME=%q\n" "${SUBDIR_NAME}"
        printf "SAVED_SAVE_DIR=%q\n" "${SAVE_DIR}"
        printf "SAVED_SAVE_FSTYPE=%q\n" "${SAVE_FSTYPE}"
        printf "SAVED_SHARE_NAME=%q\n" "${SHARE_NAME}"
        printf "SAVED_BASE_DOMAIN=%q\n" "${BASE_DOMAIN}"
        printf "SAVED_VAULT_DOMAIN=%q\n" "${VAULT_DOMAIN}"
        printf "SAVED_GITEA_DOMAIN=%q\n" "${GITEA_DOMAIN}"
        printf "SAVED_ADGUARD_DOMAIN=%q\n" "${ADGUARD_DOMAIN}"
        printf "SAVED_TORRENT_DOMAIN=%q\n" "${TORRENT_DOMAIN}"
        printf "SAVED_PROXY_DOMAIN=%q\n" "${PROXY_DOMAIN}"
        printf "SAVED_VAULT_DATA_DIR=%q\n" "${VAULT_DATA_DIR}"
        printf "SAVED_GITEA_DATA_DIR=%q\n" "${GITEA_DATA_DIR}"
        printf "SAVED_ADGUARD_WORK_DIR=%q\n" "${ADGUARD_WORK_DIR}"
        printf "SAVED_INIT_SYSTEM=%q\n" "${INIT_SYSTEM}"
        printf "SAVED_SELECTED_DOH_1=%q\n" "${SELECTED_DOH_1}"
        printf "SAVED_SELECTED_DOH_2=%q\n" "${SELECTED_DOH_2}"
        printf "SAVED_SELECTED_DOH_3=%q\n" "${SELECTED_DOH_3}"
        printf "SAVED_SELECTED_DOT_1=%q\n" "${SELECTED_DOT_1}"
        printf "SAVED_SELECTED_DOT_2=%q\n" "${SELECTED_DOT_2}"
        printf "SAVED_SELECTED_BOOTSTRAP_IPS=%q\n" "${SELECTED_BOOTSTRAP_IPS}"
        printf "SAVED_SELECTED_BOOTSTRAP_IP_1=%q\n" "${SELECTED_BOOTSTRAP_IP_1}"
        printf "SAVED_LOGS_DOMAIN=%q\n" "${LOGS_DOMAIN}"
        printf "SAVED_ENABLE_TELEGRAM=%q\n" "${ENABLE_TELEGRAM}"
        printf "SAVED_TELEGRAM_BOT_TOKEN=%q\n" "${TELEGRAM_BOT_TOKEN}"
        printf "SAVED_TELEGRAM_CHAT_ID=%q\n" "${TELEGRAM_CHAT_ID}"
        printf "SAVED_HOMELAB_VERSION=%q\n" "${HOMELAB_VERSION}"
    } > "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    chown root:root "${ENV_FILE}" 2>/dev/null || true
    log_ok "Конфигурация успешно сохранена в ${ENV_FILE}"
}

prompt_configuration() {
    print_step_header "03/11" "КОНФИГУРАЦИЯ И ВЫБОР РЕЖИМА УСТАНОВКИ"

    if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ]; then
        log_info "Режим бесшовного обновления ядра (In-Place Upgrade): интерактивные вопросы пропущены."
        log_info "Все текущие параметры, учетные записи и пути к данным сохранены без изменений."
        INSTALL_MODE=1

        # Восстановление и нормализация параметров из сохраненной конфигурации
        ENABLE_GATEWAY="${SAVED_ENABLE_GATEWAY:-${ENABLE_GATEWAY:-Y}}"
        ENABLE_VAULT="${SAVED_ENABLE_VAULT:-${ENABLE_VAULT:-Y}}"
        ENABLE_GITEA="${SAVED_ENABLE_GITEA:-${ENABLE_GITEA:-Y}}"
        ENABLE_SAMBA="${SAVED_ENABLE_SAMBA:-${ENABLE_SAMBA:-Y}}"
        ENABLE_QBIT="${SAVED_ENABLE_QBIT:-${ENABLE_QBIT:-Y}}"
        ENABLE_METUBE="${SAVED_ENABLE_METUBE:-${ENABLE_METUBE:-Y}}"
        ENABLE_NAVIDROME="${SAVED_ENABLE_NAVIDROME:-${ENABLE_NAVIDROME:-Y}}"
        SSL_MODE="${SAVED_SSL_MODE:-${SSL_MODE:-1}}"
        SUB_URL="${SAVED_SUB_URL:-${SUB_URL:-none}}"

        ADMIN_USER="${SAVED_ADMIN_USER:-${ADMIN_USER:-admin}}"
        ADMIN_USER=$(echo "${ADMIN_USER}" | tr -cd "[:alnum:]_-")
        [ -z "${ADMIN_USER}" ] && ADMIN_USER="admin"
        ADMIN_USER_SAFE=$(echo "${ADMIN_USER}" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
        [[ "${ADMIN_USER_SAFE}" =~ ^[0-9] ]] && ADMIN_USER_SAFE="u_${ADMIN_USER_SAFE}"

        MASTER_PASS="${SAVED_MASTER_PASS:-${MASTER_PASS:-}}"
        MIHOMO_SECRET="${SAVED_MIHOMO_SECRET:-${MASTER_PASS}}"
        SAMBA_PASS="${SAVED_SAMBA_PASS:-${MASTER_PASS}}"
        AGH_PASS="${SAVED_AGH_PASS:-${MASTER_PASS}}"
        VAULT_ADMIN_TOKEN="${SAVED_VAULT_ADMIN_TOKEN:-${MASTER_PASS}}"

        SAVE_DIR="${SAVED_SAVE_DIR:-${SAVE_DIR:-/opt/homelab/save}}"
        SAVE_FSTYPE="${SAVED_SAVE_FSTYPE:-${SAVE_FSTYPE:-ext4}}"
        STORAGE_MODE="${SAVED_STORAGE_MODE:-${STORAGE_MODE:-1}}"
        SUBDIR_NAME="${SAVED_SUBDIR_NAME:-${SUBDIR_NAME:-}}"
        SHARE_NAME="${SAVED_SHARE_NAME:-$(basename "${SAVE_DIR}" | tr -cd '[:alnum:]_-')}"
        [ -z "${SHARE_NAME}" ] && SHARE_NAME="storage"

        DUCKDNS_NAME="${SAVED_DUCKDNS_NAME:-}"
        DUCKDNS_TOKEN="${SAVED_DUCKDNS_TOKEN:-}"

        if [ "${SSL_MODE}" = "2" ] && [ -n "${DUCKDNS_NAME}" ]; then
            BASE_DOMAIN="${DUCKDNS_NAME}.duckdns.org"
            VAULT_DOMAIN="${SAVED_VAULT_DOMAIN:-vault.${BASE_DOMAIN}}"
            GITEA_DOMAIN="${SAVED_GITEA_DOMAIN:-git.${BASE_DOMAIN}}"
            ADGUARD_DOMAIN="${SAVED_ADGUARD_DOMAIN:-adguard.${BASE_DOMAIN}}"
            TORRENT_DOMAIN="${SAVED_TORRENT_DOMAIN:-torrent.${BASE_DOMAIN}}"
            METUBE_DOMAIN="${SAVED_METUBE_DOMAIN:-metube.${BASE_DOMAIN}}"
            MUSIC_DOMAIN="${SAVED_MUSIC_DOMAIN:-music.${BASE_DOMAIN}}"
            PROXY_DOMAIN="${SAVED_PROXY_DOMAIN:-proxy.${BASE_DOMAIN}}"
            LOGS_DOMAIN="${SAVED_LOGS_DOMAIN:-logs.${BASE_DOMAIN}}"
        else
            SSL_MODE="1"
            BASE_DOMAIN=""
            VAULT_DOMAIN="${SAVED_VAULT_DOMAIN:-vault.lan}"
            GITEA_DOMAIN="${SAVED_GITEA_DOMAIN:-git.lan}"
            ADGUARD_DOMAIN="${SAVED_ADGUARD_DOMAIN:-adguard.lan}"
            TORRENT_DOMAIN="${SAVED_TORRENT_DOMAIN:-torrent.lan}"
            METUBE_DOMAIN="${SAVED_METUBE_DOMAIN:-metube.lan}"
            MUSIC_DOMAIN="${SAVED_MUSIC_DOMAIN:-music.lan}"
            PROXY_DOMAIN="${SAVED_PROXY_DOMAIN:-proxy.lan}"
            LOGS_DOMAIN="${SAVED_LOGS_DOMAIN:-logs.lan}"
        fi

        ENABLE_TELEGRAM="${SAVED_ENABLE_TELEGRAM:-N}"
        TELEGRAM_BOT_TOKEN="${SAVED_TELEGRAM_BOT_TOKEN:-}"
        TELEGRAM_CHAT_ID="${SAVED_TELEGRAM_CHAT_ID:-}"

        local ROOT_DEV
        ROOT_DEV=$(df -P / 2>/dev/null | awk 'NR==2{print $1}' || echo "/dev/root")
        local SAVE_DEV
        SAVE_DEV=$(df -P "${SAVE_DIR}" 2>/dev/null | awk 'NR==2{print $1}' || echo "${ROOT_DEV}")

        if [ -n "${SAVED_VAULT_DATA_DIR:-}" ]; then
            VAULT_DATA_DIR="${SAVED_VAULT_DATA_DIR}"
        elif [ "${ROOT_DEV}" != "${SAVE_DEV}" ] || [ -n "${STORAGE_DEP_LINE}" ]; then
            VAULT_DATA_DIR="${SAVE_DIR}/services/vaultwarden"
        else
            VAULT_DATA_DIR="${APP_DIR}/vaultwarden"
        fi

        if [ -n "${SAVED_GITEA_DATA_DIR:-}" ]; then
            GITEA_DATA_DIR="${SAVED_GITEA_DATA_DIR}"
        elif [ "${ROOT_DEV}" != "${SAVE_DEV}" ] || [ -n "${STORAGE_DEP_LINE}" ]; then
            GITEA_DATA_DIR="${SAVE_DIR}/services/gitea"
        else
            GITEA_DATA_DIR="${APP_DIR}/gitea"
        fi

        if [ -n "${SAVED_ADGUARD_WORK_DIR:-}" ]; then
            ADGUARD_WORK_DIR="${SAVED_ADGUARD_WORK_DIR}"
        elif [ "${ROOT_DEV}" != "${SAVE_DEV}" ] || [ -n "${STORAGE_DEP_LINE}" ]; then
            ADGUARD_WORK_DIR="${SAVE_DIR}/services/adguard_work"
        else
            ADGUARD_WORK_DIR="${APP_DIR}/adguard/work"
        fi

        save_configuration
        return 0
    fi

    echo -e "  ${CLR_WHITE}Выберите вариант развертывания:${CLR_RESET}"
    echo -e "    ${CLR_GREEN}1) Экспресс-установка${CLR_RESET} (Всё включено, авто-настройка, *.lan) ${CLR_DIM}[Enter]${CLR_RESET}"
    echo -e "    ${CLR_YELLOW}2) Расширенная настройка${CLR_RESET} (Выбор дисков, Btrfs, LUKS2 шифрование, DuckDNS)"
    echo -e "    ${CLR_RED}3) Сброс стека${CLR_RESET} (Остановка контейнеров, очистка конфигов и запуск с нуля)"
    echo ""
    prompt_read "  [?] Ваш выбор [1/2/3] [1]: " INSTALL_MODE
    INSTALL_MODE=${INSTALL_MODE:-1}
    while [[ ! "${INSTALL_MODE}" =~ ^[123]$ ]]; do
        prompt_read "  [-] Пожалуйста, выберите 1, 2 или 3 [1]: " INSTALL_MODE
        INSTALL_MODE=${INSTALL_MODE:-1}
    done
    echo ""

    if [ "$INSTALL_MODE" = "3" ]; then
        echo ""
        log_warn "РЕЖИМ ПОЛНОГО СБРОСА: Будут остановлены все контейнеры и удалены конфигурации стека!"
        prompt_read "  [?] Подтвердите сброс (введите 'yes'): " CONFIRM_RESET
        if [[ ! "${CONFIRM_RESET:-}" =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Операция отменена."
            exit 0
        fi

        log_info "Остановка системных служб и таймеров..."
        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            systemctl disable --now homelab.service 2>/dev/null || true
            systemctl disable --now network-gateway-watchdog.timer 2>/dev/null || true
            systemctl disable --now network-gateway-watchdog.service 2>/dev/null || true
            systemctl disable --now vaultwarden-backup.timer 2>/dev/null || true
            systemctl disable --now vaultwarden-backup.service 2>/dev/null || true
            systemctl disable --now gitea-backup.timer 2>/dev/null || true
            systemctl disable --now gitea-backup.service 2>/dev/null || true
            systemctl disable --now navidrome-backup.timer 2>/dev/null || true
            systemctl disable --now navidrome-backup.service 2>/dev/null || true
            rm -f /etc/systemd/system/homelab.service /etc/systemd/system/network-gateway-watchdog.* /etc/systemd/system/vaultwarden-backup.* /etc/systemd/system/gitea-backup.* /etc/systemd/system/navidrome-backup.*
            systemctl daemon-reload >/dev/null 2>&1 || true
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            rc-service homelab stop 2>/dev/null || true
            rc-update del homelab default 2>/dev/null || true
            rc-service homelab-storage stop 2>/dev/null || true
            rc-update del homelab-storage boot 2>/dev/null || true
            rc-update del homelab-storage default 2>/dev/null || true
            rc-service zram-swap stop 2>/dev/null || true
            rc-update del zram-swap default 2>/dev/null || true
            rm -f /etc/init.d/homelab /etc/init.d/homelab-storage /etc/init.d/zram-swap
            sed -i '/backup_vaultwarden\.sh/d; /backup_gitea\.sh/d; /backup_navidrome\.sh/d; /gateway-watchdog\.sh/d' /etc/crontabs/root 2>/dev/null || true
            touch /etc/crontabs/cron.update 2>/dev/null || true
        fi

        log_info "Остановка и удаление контейнеров Docker..."
        if [ -d "${APP_DIR}" ]; then
            (cd "${APP_DIR}" && dc down --remove-orphans 2>/dev/null || true)
        fi
        docker stop adguardhome mihomo caddy vaultwarden gitea qbittorrent metube navidrome samba dozzle watchtower autoheal 2>/dev/null || true
        docker rm -f adguardhome mihomo caddy vaultwarden gitea qbittorrent metube navidrome samba dozzle watchtower autoheal 2>/dev/null || true

        log_info "Очистка служебных файлов и конфигураций..."
        local BACKUP_CERTS="/tmp/caddy_certificates_backup_$$"
        rm -rf "${BACKUP_CERTS}"
        if [ -d "${APP_DIR}/caddy/data/caddy/certificates" ]; then
            log_info "Сохранение существующих SSL-сертификатов Caddy..."
            cp -r "${APP_DIR}/caddy/data/caddy/certificates" "${BACKUP_CERTS}" 2>/dev/null || true
        fi

        rm -rf "${APP_DIR}/adguard" "${APP_DIR}/mihomo" "${APP_DIR}/caddy" "${APP_DIR}/metube" "${APP_DIR}/vaultwarden" "${APP_DIR}/gitea" "${APP_DIR}/qbittorrent" "${APP_DIR}/configs/navidrome" "${APP_DIR}/backup_*.sh" "${ENV_FILE}"

        if [ -d "${BACKUP_CERTS}" ]; then
            mkdir -p "${APP_DIR}/caddy/data/caddy"
            cp -r "${BACKUP_CERTS}" "${APP_DIR}/caddy/data/caddy/certificates" 2>/dev/null || true
            rm -rf "${BACKUP_CERTS}"
            log_ok "SSL-сертификаты успешно сохранены для последующего использования"
        fi

        rm -f /usr/local/bin/gateway-watchdog.sh /usr/local/bin/homelab-unlock /usr/local/bin/homelab /usr/local/bin/homelab-notify /usr/local/bin/mihomo /usr/local/bin/adguard /usr/local/bin/adguardhome
        rm -f /opt/homelab/diagnostic_report.log
        local USER_HOME
        USER_HOME=$(eval echo ~"${TARGET_USER}" 2>/dev/null || echo "/home/${TARGET_USER}")
        rm -f "${USER_HOME}/diagnostic_report.log" 2>/dev/null || true

        log_info "Очистка правил межсетевого экрана (декларативная таблица inet homelab в nftables)..."
        if command -v nft >/dev/null 2>&1; then
            nft delete table inet homelab 2>/dev/null || true
            rm -f /etc/nftables.d/homelab.nft 2>/dev/null || true
            sed -i '/include.*homelab\.nft/d' /etc/nftables.conf /etc/nftables.nft 2>/dev/null || true
        fi

        log_info "Восстановление стандартных записей в /etc/hosts..."
        sed -i '/\.lan$/d; /\.duckdns\.org$/d' /etc/hosts 2>/dev/null || true

        echo ""
        log_ok "Сброс стека успешно завершен! Все компоненты очищены."
        exit 0
    fi

    if [ "$INSTALL_MODE" = "1" ]; then
        log_info "Выбран режим 'Экспресс-установка' (Zero-Touch): все сервисы будут включены."
        STORAGE_MODE="1"
        SUBDIR_NAME=""
        local USER_HOME
        USER_HOME=$(eval echo ~"${TARGET_USER}" 2>/dev/null || echo "/home/${TARGET_USER}")
        DEF_SAVE_DIR="${SAVED_SAVE_DIR:-${USER_HOME}/save}"
        prompt_read "  [?] Путь к каталогу данных [Enter - ${DEF_SAVE_DIR}]: " INPUT_SAVE_DIR
        SAVE_DIR=${INPUT_SAVE_DIR:-${DEF_SAVE_DIR}}
        mkdir -p "${SAVE_DIR}"
        SAVE_FSTYPE=$(findmnt -n -o FSTYPE -T "${SAVE_DIR}" 2>/dev/null || df -T "${SAVE_DIR}" 2>/dev/null | awk 'NR==2{print $2}' || echo "ext4")

        ENABLE_GATEWAY="${SAVED_ENABLE_GATEWAY:-Y}"
        ENABLE_VAULT="${SAVED_ENABLE_VAULT:-Y}"
        ENABLE_GITEA="${SAVED_ENABLE_GITEA:-Y}"
        ENABLE_SAMBA="${SAVED_ENABLE_SAMBA:-Y}"
        ENABLE_QBIT="${SAVED_ENABLE_QBIT:-Y}"
        ENABLE_METUBE="${SAVED_ENABLE_METUBE:-Y}"
        ENABLE_NAVIDROME="${SAVED_ENABLE_NAVIDROME:-Y}"
        SSL_MODE="${SAVED_SSL_MODE:-1}"

        echo ""
        echo -e "  ${CLR_CYAN}--- Экспресс-параметры шлюза и учетных записей ---${CLR_RESET}"
        DEF_SUB="${SAVED_SUB_URL:-none}"
        prompt_read "  [?] Ссылка на Clash/Mihomo подписку [Enter - ${DEF_SUB}]: " INPUT_SUB_URL
        SUB_URL=${INPUT_SUB_URL:-${DEF_SUB}}
        if [ -z "$SUB_URL" ] || [ "$SUB_URL" = "none" ] || [ "$SUB_URL" = "skip" ] || [ "$SUB_URL" = "direct" ] || [ "$SUB_URL" = "-" ]; then
            SUB_URL="none"
            log_ok "Режим шлюза: DIRECT (чистая маршрутизация, без прокси)"
        else
            log_ok "Подписка сохранена"
        fi

        DEF_ADMIN_USER="${SAVED_ADMIN_USER:-${TARGET_USER}}"
        prompt_read "  [?] Имя пользователя для веб-панелей и Samba [Enter - ${DEF_ADMIN_USER}]: " INPUT_ADMIN_USER
        ADMIN_USER=${INPUT_ADMIN_USER:-${DEF_ADMIN_USER}}
        ADMIN_USER=$(echo "${ADMIN_USER}" | tr -cd "[:alnum:]_-")
        [ -z "${ADMIN_USER}" ] && ADMIN_USER="admin"
        ADMIN_USER_SAFE=$(echo "${ADMIN_USER}" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
        [[ "${ADMIN_USER_SAFE}" =~ ^[0-9] ]] && ADMIN_USER_SAFE="u_${ADMIN_USER_SAFE}"

        GEN_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(12))" 2>/dev/null || echo "SecurePass$(date +%s)")
        if [ -n "${SAVED_MASTER_PASS:-}" ]; then
            PROMPT_PASS_MSG="Enter - оставить прежний: ${SAVED_MASTER_PASS}"
        else
            PROMPT_PASS_MSG="Enter - сгенерировать: ${GEN_PASS}"
        fi
        DEF_PASS="${SAVED_MASTER_PASS:-${GEN_PASS}}"
        prompt_read "  [?] Единый мастер-пароль [${PROMPT_PASS_MSG}]: " INPUT_PASS
        MASTER_PASS=${INPUT_PASS:-${DEF_PASS}}
        MIHOMO_SECRET="${MASTER_PASS}"
        SAMBA_PASS="${MASTER_PASS}"
        AGH_PASS="${MASTER_PASS}"
        VAULT_ADMIN_TOKEN="${SAVED_VAULT_ADMIN_TOKEN:-${MASTER_PASS}}"

        DUCKDNS_NAME=""
        DUCKDNS_TOKEN=""
        BASE_DOMAIN=""
        VAULT_DOMAIN="vault.lan"
        GITEA_DOMAIN="git.lan"
        ADGUARD_DOMAIN="adguard.lan"
        TORRENT_DOMAIN="torrent.lan"
        METUBE_DOMAIN="metube.lan"
        MUSIC_DOMAIN="music.lan"
        PROXY_DOMAIN="proxy.lan"
        LOGS_DOMAIN="logs.lan"
        ENABLE_TELEGRAM="${SAVED_ENABLE_TELEGRAM:-N}"
        TELEGRAM_BOT_TOKEN="${SAVED_TELEGRAM_BOT_TOKEN:-}"
        TELEGRAM_CHAT_ID="${SAVED_TELEGRAM_CHAT_ID:-}"
    else
        local ROOT_FSTYPE
        ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || df -T / 2>/dev/null | awk 'NR==2{print $2}' || echo "ext4")
        local ROOT_AVAIL
        ROOT_AVAIL=$(df -h / 2>/dev/null | awk 'NR==2{print $4}' || echo "N/A")
        local USER_HOME
        USER_HOME=$(eval echo ~"${TARGET_USER}" 2>/dev/null || echo "/home/${TARGET_USER}")
        local DEF_ROOT_PATH="${SAVED_SAVE_DIR:-${USER_HOME}/save}"

        echo -e "  ${CLR_NEON_PURPLE}╭── НАСТРОЙКА ДИСКОВОГО ХРАНИЛИЩА ───────────────────────────────────────────╮${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│                                                                             │${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│  ${CLR_NEON_GREEN}[1] Системный диск${CLR_RESET} ${CLR_DIM}[Enter] (Раздел ОС: ${DEF_ROOT_PATH})${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│      ${CLR_WHITE}Файловая система:${CLR_RESET} ${CLR_NEON_GOLD}${ROOT_FSTYPE}${CLR_RESET}  ${CLR_WHITE}Доступно:${CLR_RESET} ${CLR_NEON_GREEN}${ROOT_AVAIL}${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│                                                                             │${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│  ${CLR_CYAN}ВНЕШНИЕ / ДОПОЛНИТЕЛЬНЫЕ ДИСКИ (Системный диск исключен из списка):       │${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│  ${CLR_WHITE}[2] Подключить существующий раздел БЕЗ шифрования                         │${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│  ${CLR_WHITE}[3] Отформатировать диск в Btrfs (zstd сжатие, ДАННЫЕ УНИЧТОЖАЮТСЯ)        │${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│  ${CLR_WHITE}[4] Подключить существующий крипто-диск LUKS2                                │${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│  ${CLR_WHITE}[5] Отформатировать в LUKS2 + Btrfs (Argon2id, ДАННЫЕ УНИЧТОЖАЮТСЯ)         │${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}╰─────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
        DEF_STORAGE_MODE="${SAVED_STORAGE_MODE:-1}"
        prompt_read "  [?] Выберите вариант [1-5] [${DEF_STORAGE_MODE}]: " STORAGE_MODE
        STORAGE_MODE=${STORAGE_MODE:-${DEF_STORAGE_MODE}}

        local SYSTEMD_TIMEOUT="x-systemd.device-timeout=15s,"
        [ "${INIT_SYSTEM}" = "openrc" ] && SYSTEMD_TIMEOUT=""

        if [ "$STORAGE_MODE" = "2" ]; then
            select_disk_device
            DEV_UUID=$(blkid -s UUID -o value "${CHOSEN_DEV}" || true)
            DEV_FSTYPE=$(blkid -s TYPE -o value "${CHOSEN_DEV}" || true)
            SAVE_FSTYPE="${DEV_FSTYPE:-ext4}"

            mkdir -p "${MOUNT_ROOT}"
            MOUNT_OPTS="defaults,noatime,nofail,${SYSTEMD_TIMEOUT}"
            MOUNT_OPTS="${MOUNT_OPTS%,}"
            if [[ "$DEV_FSTYPE" =~ ^(exfat|ntfs|vfat)$ ]]; then
                MOUNT_OPTS="${MOUNT_OPTS},uid=${USER_UID},gid=${USER_GID},umask=000,iocharset=utf8"
            elif [ "$DEV_FSTYPE" = "btrfs" ]; then
                local ROT=$(cat "/sys/block/$(basename "$CHOSEN_DEV")/queue/rotational" 2>/dev/null || echo "1")
                if [ "$ROT" = "0" ]; then
                    MOUNT_OPTS="${MOUNT_OPTS},compress=zstd,discard=async"
                else
                    MOUNT_OPTS="${MOUNT_OPTS},compress=zstd,autodefrag"
                fi
            fi

            mountpoint -q "${MOUNT_ROOT}" || mount -o "${MOUNT_OPTS}" "${CHOSEN_DEV}" "${MOUNT_ROOT}"
            [ "$DEV_FSTYPE" = "btrfs" ] && chown -R "${USER_UID}:${USER_GID}" "${MOUNT_ROOT}" 2>/dev/null || true

            if [ -n "${DEV_UUID}" ] && ! grep -q "${DEV_UUID}" /etc/fstab 2>/dev/null; then
                echo "UUID=${DEV_UUID} ${MOUNT_ROOT} ${DEV_FSTYPE:-auto} ${MOUNT_OPTS} 0 0" >> /etc/fstab
            fi

            [ "${INIT_SYSTEM}" = "systemd" ] && STORAGE_DEP_LINE="RequiresMountsFor=${MOUNT_ROOT}"
            DEF_SUBDIR="${SAVED_SUBDIR_NAME:-save}"
            prompt_read "  [?] Имя подкаталога для данных [${DEF_SUBDIR}]: " SUBDIR_NAME
            SUBDIR_NAME=${SUBDIR_NAME:-${DEF_SUBDIR}}
            SAVE_DIR="${MOUNT_ROOT}/${SUBDIR_NAME}"
            mkdir -p "${SAVE_DIR}"

        elif [ "$STORAGE_MODE" = "3" ]; then
            select_disk_device
            SAVE_FSTYPE="btrfs"
            echo ""
            log_warn "Все данные на ${CHOSEN_DEV} будут уничтожены!"
            prompt_read "  [?] Подтвердите форматирование (введите 'yes'): " CONFIRM_WIPE
            if [[ ! "${CONFIRM_WIPE:-}" =~ ^[Yy][Ee][Ss]$ ]]; then
                log_info "Отмена операции."
                exit 1
            fi

            assert_safe_device "${CHOSEN_DEV}"
            release_device "${CHOSEN_DEV}"
            mkfs.btrfs -f -L "HOMELAB" "${CHOSEN_DEV}"
            DEV_UUID=$(blkid -s UUID -o value "${CHOSEN_DEV}")

            mkdir -p "${MOUNT_ROOT}"
            local ROT=$(cat "/sys/block/$(basename "$CHOSEN_DEV")/queue/rotational" 2>/dev/null || echo "1")
            local BTRFS_DISCARD="discard=async"
            [ "$ROT" = "1" ] && BTRFS_DISCARD="autodefrag"
            MOUNT_OPTS="defaults,noatime,compress=zstd,${BTRFS_DISCARD},nofail,${SYSTEMD_TIMEOUT}"
            MOUNT_OPTS="${MOUNT_OPTS%,}"
            mount -o "${MOUNT_OPTS}" "${CHOSEN_DEV}" "${MOUNT_ROOT}"
            chown -R "${USER_UID}:${USER_GID}" "${MOUNT_ROOT}"

            if [ -n "${DEV_UUID}" ] && ! grep -q "${DEV_UUID}" /etc/fstab 2>/dev/null; then
                echo "UUID=${DEV_UUID} ${MOUNT_ROOT} btrfs ${MOUNT_OPTS} 0 0" >> /etc/fstab
            fi

            [ "${INIT_SYSTEM}" = "systemd" ] && STORAGE_DEP_LINE="RequiresMountsFor=${MOUNT_ROOT}"
            DEF_SUBDIR="${SAVED_SUBDIR_NAME:-save}"
            prompt_read "  [?] Имя подкаталога для данных [${DEF_SUBDIR}]: " SUBDIR_NAME
            SUBDIR_NAME=${SUBDIR_NAME:-${DEF_SUBDIR}}
            SAVE_DIR="${MOUNT_ROOT}/${SUBDIR_NAME}"
            mkdir -p "${SAVE_DIR}"

        elif [ "$STORAGE_MODE" = "4" ] || [ "$STORAGE_MODE" = "5" ]; then
            select_disk_device

            if [ "$STORAGE_MODE" = "5" ]; then
                echo ""
                log_warn "Накопитель ${CHOSEN_DEV} будет полностью зашифрован LUKS2 (Argon2id) и отформатирован в Btrfs!"
                prompt_read "  [?] Подтвердите форматирование (введите 'yes'): " CONFIRM_WIPE
                if [[ ! "${CONFIRM_WIPE:-}" =~ ^[Yy][Ee][Ss]$ ]]; then
                    log_info "Отмена операции."
                    exit 1
                fi

                assert_safe_device "${CHOSEN_DEV}"
                release_device "${CHOSEN_DEV}"

                local CIPHER_OPT=""
                if [ "${HAS_HARDWARE_AES}" -eq 0 ] && [[ "${SYSTEM_ARCH}" =~ ^(arm|aarch64) ]]; then
                    log_info "Аппаратный AES отсутствует на ${SYSTEM_ARCH}. Использование высокоскоростного ChaCha20-Poly1305."
                    CIPHER_OPT="--cipher chacha20-poly1305"
                fi

                log_info "Создание крипто-тома LUKS2 (задайте пароль диска):"
                # shellcheck disable=SC2086
                cryptsetup luksFormat --type luks2 --pbkdf argon2id ${CIPHER_OPT} "${CHOSEN_DEV}"

                log_info "Открытие тома..."
                cryptsetup open "${CHOSEN_DEV}" "${LUKS_MAP_NAME}"

                log_info "Создание файловой системы Btrfs..."
                mkfs.btrfs -f -L "HOMELAB" "/dev/mapper/${LUKS_MAP_NAME}"
            fi

            if [ "$STORAGE_MODE" = "4" ]; then
                if [ ! -e "/dev/mapper/${LUKS_MAP_NAME}" ]; then
                    log_info "Введите пароль для расшифровки ${CHOSEN_DEV}:"
                    cryptsetup open "${CHOSEN_DEV}" "${LUKS_MAP_NAME}"
                fi
            fi

            MAPPER_DEV="/dev/mapper/${LUKS_MAP_NAME}"
            DEV_FSTYPE=$(blkid -s TYPE -o value "${MAPPER_DEV}" || echo "btrfs")
            SAVE_FSTYPE="${DEV_FSTYPE:-btrfs}"

            local ROT=$(cat "/sys/block/$(basename "$CHOSEN_DEV")/queue/rotational" 2>/dev/null || echo "1")
            local BTRFS_DISCARD="discard=async"
            [ "$ROT" = "1" ] && BTRFS_DISCARD="autodefrag"
            MOUNT_OPTS="defaults,noatime,nofail,${SYSTEMD_TIMEOUT}"
            MOUNT_OPTS="${MOUNT_OPTS%,}"
            [ "$DEV_FSTYPE" = "btrfs" ] && MOUNT_OPTS="${MOUNT_OPTS},compress=zstd,${BTRFS_DISCARD}"

            mkdir -p "${MOUNT_ROOT}"
            mountpoint -q "${MOUNT_ROOT}" || mount -o "${MOUNT_OPTS}" "${MAPPER_DEV}" "${MOUNT_ROOT}"
            [ "$DEV_FSTYPE" = "btrfs" ] && chown -R "${USER_UID}:${USER_GID}" "${MOUNT_ROOT}" 2>/dev/null || true

            DEF_SUBDIR="${SAVED_SUBDIR_NAME:-save}"
            prompt_read "  [?] Имя подкаталога для данных [${DEF_SUBDIR}]: " SUBDIR_NAME
            SUBDIR_NAME=${SUBDIR_NAME:-${DEF_SUBDIR}}
            SAVE_DIR="${MOUNT_ROOT}/${SUBDIR_NAME}"
            mkdir -p "${SAVE_DIR}"

            log_info "Настройка авторазблокировки при старте через ключ-файл..."
            DEV_UUID=$(blkid -s UUID -o value "${CHOSEN_DEV}")

            KEY_DIR="/etc/cryptsetup-keys.d"
            KEY_FILE="${KEY_DIR}/storage_${LUKS_MAP_NAME}.key"

            mkdir -p "${KEY_DIR}"
            chmod 700 "${KEY_DIR}"

            if [ ! -f "${KEY_FILE}" ]; then
                log_info "Генерация случайного крипто-ключа авторазблокировки..."
                dd if=/dev/urandom of="${KEY_FILE}" bs=512 count=1 status=none
                chmod 400 "${KEY_FILE}"

                log_info "Добавление ключа в слот LUKS2 (введите пароль диска):"
                cryptsetup luksAddKey "${CHOSEN_DEV}" "${KEY_FILE}"
            fi

            if ! grep -q "${LUKS_MAP_NAME}" /etc/crypttab 2>/dev/null; then
                echo "${LUKS_MAP_NAME} UUID=${DEV_UUID} ${KEY_FILE} luks,discard,nofail,timeout=15" >> /etc/crypttab
            fi

            if ! grep -q "${MOUNT_ROOT}" /etc/fstab 2>/dev/null; then
                echo "${MAPPER_DEV} ${MOUNT_ROOT} ${DEV_FSTYPE} ${MOUNT_OPTS} 0 0" >> /etc/fstab
            fi

            if [ "${INIT_SYSTEM}" = "openrc" ]; then
                cat << EOF_CRYPT_RC > /etc/init.d/homelab-storage
#!/sbin/openrc-run
description="Homelab Encrypted Storage Unlock & Mount"
depend() {
    before docker homelab
    after localmount
}
start() {
    ebegin "Unlocking and mounting homelab storage"
    if [ ! -e "${MAPPER_DEV}" ] && [ -f "${KEY_FILE}" ]; then
        cryptsetup open "${CHOSEN_DEV}" "${LUKS_MAP_NAME}" --key-file "${KEY_FILE}"
    fi
    mkdir -p "${MOUNT_ROOT}"
    mountpoint -q "${MOUNT_ROOT}" || mount -o "${MOUNT_OPTS}" "${MAPPER_DEV}" "${MOUNT_ROOT}"
    eend $?
}
stop() {
    ebegin "Unmounting and closing homelab storage"
    if mountpoint -q "${MOUNT_ROOT}"; then
        umount -R "${MOUNT_ROOT}" 2>/dev/null || true
    fi
    if [ -e "${MAPPER_DEV}" ]; then
        cryptsetup close "${LUKS_MAP_NAME}" 2>/dev/null || true
    fi
    eend 0
}
EOF_CRYPT_RC
                chmod 755 /etc/init.d/homelab-storage
                rc-update add homelab-storage boot >/dev/null 2>&1 || rc-update add homelab-storage default >/dev/null 2>&1 || true
            fi

            [ "${INIT_SYSTEM}" = "systemd" ] && STORAGE_DEP_LINE="RequiresMountsFor=${MOUNT_ROOT}"
            log_ok "Авторазблокировка успешно настроена!"

            cat << EOF_UNLOCK > /usr/local/bin/homelab-unlock
#!/usr/bin/env bash
set -euo pipefail
if [ "\${EUID:-\$(id -u)}" -ne 0 ]; then
    echo "[-] Запустите через sudo: sudo homelab-unlock"
    exit 1
fi
if [ ! -e "${MAPPER_DEV}" ]; then
    echo "[*] Разблокировка ${CHOSEN_DEV}..."
    cryptsetup open "${CHOSEN_DEV}" "${LUKS_MAP_NAME}"
fi
mkdir -p "${MOUNT_ROOT}"
mountpoint -q "${MOUNT_ROOT}" || mount -o "${MOUNT_OPTS}" "${MAPPER_DEV}" "${MOUNT_ROOT}"
echo "[*] Запуск сервисов Docker..."
cd "${APP_DIR}" && (command -v dc >/dev/null 2>&1 && dc up -d || docker compose up -d)
echo "[+] Диск смонтирован, сервисы готовы к работе!"
EOF_UNLOCK
            chmod 750 /usr/local/bin/homelab-unlock
        else
            SUBDIR_NAME=""
            local USER_HOME
            USER_HOME=$(eval echo ~"${TARGET_USER}" 2>/dev/null || echo "/home/${TARGET_USER}")
            DEF_SAVE_DIR="${SAVED_SAVE_DIR:-${USER_HOME}/save}"
            prompt_read "  [?] Каталог данных на системном диске [${DEF_SAVE_DIR}]: " INPUT_SAVE_DIR
            SAVE_DIR=${INPUT_SAVE_DIR:-${DEF_SAVE_DIR}}
            mkdir -p "${SAVE_DIR}"
            SAVE_FSTYPE=$(findmnt -n -o FSTYPE -T "${SAVE_DIR}" 2>/dev/null || df -T "${SAVE_DIR}" 2>/dev/null | awk 'NR==2{print $2}' || echo "${ROOT_FSTYPE:-ext4}")
        fi

        echo ""
        echo -e "  ${CLR_CYAN}--- Выбор устанавливаемых компонентов ---${CLR_RESET}"
        prompt_read "  [?] Установить сетевой шлюз (AdGuard + Mihomo TUN)? [Y/n] [${SAVED_ENABLE_GATEWAY:-Y}]: " ENABLE_GATEWAY
        ENABLE_GATEWAY=$(normalize_yn "${ENABLE_GATEWAY:-${SAVED_ENABLE_GATEWAY:-Y}}" "Y")

        prompt_read "  [?] Установить Vaultwarden (Менеджер паролей)? [Y/n] [${SAVED_ENABLE_VAULT:-Y}]: " ENABLE_VAULT
        ENABLE_VAULT=$(normalize_yn "${ENABLE_VAULT:-${SAVED_ENABLE_VAULT:-Y}}" "Y")

        prompt_read "  [?] Установить Gitea (Git-сервер)? [Y/n] [${SAVED_ENABLE_GITEA:-Y}]: " ENABLE_GITEA
        ENABLE_GITEA=$(normalize_yn "${ENABLE_GITEA:-${SAVED_ENABLE_GITEA:-Y}}" "Y")

        prompt_read "  [?] Установить Samba (Сетевая папка с WSDD2)? [Y/n] [${SAVED_ENABLE_SAMBA:-Y}]: " ENABLE_SAMBA
        ENABLE_SAMBA=$(normalize_yn "${ENABLE_SAMBA:-${SAVED_ENABLE_SAMBA:-Y}}" "Y")

        prompt_read "  [?] Установить qBittorrent + VueTorrent (Торренты/Загрузки)? [Y/n] [${SAVED_ENABLE_QBIT:-Y}]: " ENABLE_QBIT
        ENABLE_QBIT=$(normalize_yn "${ENABLE_QBIT:-${SAVED_ENABLE_QBIT:-Y}}" "Y")

        prompt_read "  [?] Установить MeTube (Web-загрузчик видео и аудио)? [Y/n] [${SAVED_ENABLE_METUBE:-Y}]: " ENABLE_METUBE
        ENABLE_METUBE=$(normalize_yn "${ENABLE_METUBE:-${SAVED_ENABLE_METUBE:-Y}}" "Y")

        prompt_read "  [?] Установить Navidrome (Hi-Fi Музыкальный стриминг, аналог Spotify)? [Y/n] [${SAVED_ENABLE_NAVIDROME:-Y}]: " ENABLE_NAVIDROME
        ENABLE_NAVIDROME=$(normalize_yn "${ENABLE_NAVIDROME:-${SAVED_ENABLE_NAVIDROME:-Y}}" "Y")

        echo ""
        echo -e "  ${CLR_CYAN}--- Настройка SSL сертификатов ---${CLR_RESET}"
        echo "    1) Локальный Caddy (*.lan, доверие через CA сертификат root.crt)"
        echo "    2) DuckDNS + Let's Encrypt (публичный Wildcard SSL через DNS-01)"
        prompt_read "  [?] Режим SSL [1/2] [${SAVED_SSL_MODE:-1}]: " SSL_MODE
        SSL_MODE=${SSL_MODE:-${SAVED_SSL_MODE:-1}}

        if [ "$SSL_MODE" = "2" ]; then
            prompt_read "  [?] Поддомен DuckDNS [${SAVED_DUCKDNS_NAME:-}]: " DUCKDNS_NAME
            DUCKDNS_NAME=${DUCKDNS_NAME:-${SAVED_DUCKDNS_NAME:-}}
            DUCKDNS_NAME=$(echo "${DUCKDNS_NAME}" | sed "s/\.duckdns\.org$//")
            while [ -z "$DUCKDNS_NAME" ]; do
                prompt_read "  [-] Имя обязательно: " DUCKDNS_NAME
            done
            prompt_read "  [?] Токен DuckDNS [${SAVED_DUCKDNS_TOKEN:-}]: " DUCKDNS_TOKEN
            DUCKDNS_TOKEN=${DUCKDNS_TOKEN:-${SAVED_DUCKDNS_TOKEN:-}}
            while [ -z "$DUCKDNS_TOKEN" ]; do
                prompt_read "  [-] Токен обязателен: " DUCKDNS_TOKEN
            done

            BASE_DOMAIN="${DUCKDNS_NAME}.duckdns.org"
            VAULT_DOMAIN="vault.${BASE_DOMAIN}"
            GITEA_DOMAIN="git.${BASE_DOMAIN}"
            ADGUARD_DOMAIN="adguard.${BASE_DOMAIN}"
            TORRENT_DOMAIN="torrent.${BASE_DOMAIN}"
            METUBE_DOMAIN="metube.${BASE_DOMAIN}"
            MUSIC_DOMAIN="music.${BASE_DOMAIN}"
            PROXY_DOMAIN="proxy.${BASE_DOMAIN}"
            LOGS_DOMAIN="logs.${BASE_DOMAIN}"

            log_info "Синхронизация DuckDNS DNS-записи (${BASE_DOMAIN} -> ${LOCAL_IP})..."
            curl -fsSL -m 10 "https://www.duckdns.org/update?domains=${DUCKDNS_NAME}&token=${DUCKDNS_TOKEN}&ip=${LOCAL_IP}" >/dev/null 2>&1 || true
        else
            SSL_MODE="1"
            DUCKDNS_NAME=""
            DUCKDNS_TOKEN=""
            BASE_DOMAIN=""
            VAULT_DOMAIN="vault.lan"
            GITEA_DOMAIN="git.lan"
            ADGUARD_DOMAIN="adguard.lan"
            TORRENT_DOMAIN="torrent.lan"
            METUBE_DOMAIN="metube.lan"
            MUSIC_DOMAIN="music.lan"
            PROXY_DOMAIN="proxy.lan"
            LOGS_DOMAIN="logs.lan"
        fi

        SUB_URL="${SAVED_SUB_URL:-none}"
        if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
            prompt_read "  [?] Ссылка на Clash/Mihomo подписку (Enter для DIRECT) [${SAVED_SUB_URL:-none}]: " SUB_URL
            SUB_URL=${SUB_URL:-${SAVED_SUB_URL:-none}}
            if [ -z "$SUB_URL" ] || [ "$SUB_URL" = "none" ] || [ "$SUB_URL" = "skip" ] || [ "$SUB_URL" = "direct" ] || [ "$SUB_URL" = "-" ]; then
                SUB_URL="none"
                log_ok "Режим шлюза: DIRECT (чистая маршрутизация, без прокси)"
            else
                log_ok "Подписка сохранена"
            fi
        fi

        echo ""
        echo -e "  ${CLR_CYAN}--- Пользователь и пароли ---${CLR_RESET}"
        DEF_ADMIN_USER="${SAVED_ADMIN_USER:-${TARGET_USER}}"
        prompt_read "  [?] Имя пользователя для веб-панелей и Samba [${DEF_ADMIN_USER}]: " INPUT_ADMIN_USER
        ADMIN_USER=${INPUT_ADMIN_USER:-${DEF_ADMIN_USER}}
        ADMIN_USER=$(echo "${ADMIN_USER}" | tr -cd "[:alnum:]_-")
        [ -z "${ADMIN_USER}" ] && ADMIN_USER="admin"
        ADMIN_USER_SAFE=$(echo "${ADMIN_USER}" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
        [[ "${ADMIN_USER_SAFE}" =~ ^[0-9] ]] && ADMIN_USER_SAFE="u_${ADMIN_USER_SAFE}"

        GEN_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(12))" 2>/dev/null || echo "SecurePass$(date +%s)")
        if [ -n "${SAVED_MASTER_PASS:-}" ]; then
            PROMPT_PASS_MSG="Enter - оставить прежний: ${SAVED_MASTER_PASS}"
        else
            PROMPT_PASS_MSG="Enter - сгенерировать: ${GEN_PASS}"
        fi
        prompt_read "  [?] Единый мастер-пароль [${PROMPT_PASS_MSG}]: " INPUT_MASTER_PASS
        MASTER_PASS=${INPUT_MASTER_PASS:-${SAVED_MASTER_PASS:-${GEN_PASS}}}
        SAMBA_PASS="${MASTER_PASS}"
        AGH_PASS="${MASTER_PASS}"
        MIHOMO_SECRET="${MASTER_PASS}"

        if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
            DEF_VAULT_TOKEN="${SAVED_VAULT_ADMIN_TOKEN:-${MASTER_PASS}}"
            prompt_read "  [?] Токен администратора Vaultwarden (/admin) [${DEF_VAULT_TOKEN}]: " INPUT_VAULT_TOKEN
            VAULT_ADMIN_TOKEN=${INPUT_VAULT_TOKEN:-${DEF_VAULT_TOKEN}}
        else
            VAULT_ADMIN_TOKEN="${SAVED_VAULT_ADMIN_TOKEN:-${MASTER_PASS}}"
        fi

        echo ""
        echo -e "  ${CLR_CYAN}--- Системные оповещения в Telegram (Сбои и Бэкапы) ---${CLR_RESET}"
        prompt_read "  [?] Настроить аварийные Telegram-оповещения? [y/N] [${SAVED_ENABLE_TELEGRAM:-N}]: " INPUT_ENABLE_TG
        ENABLE_TELEGRAM=$(normalize_yn "${INPUT_ENABLE_TG:-${SAVED_ENABLE_TELEGRAM:-N}}" "N")
        if [[ "${ENABLE_TELEGRAM}" =~ ^[Yy]$ ]]; then
            prompt_read "  [?] Telegram Bot Token [${SAVED_TELEGRAM_BOT_TOKEN:-}]: " INPUT_TG_TOKEN
            TELEGRAM_BOT_TOKEN=${INPUT_TG_TOKEN:-${SAVED_TELEGRAM_BOT_TOKEN:-}}
            prompt_read "  [?] Telegram Chat ID [${SAVED_TELEGRAM_CHAT_ID:-}]: " INPUT_TG_CHAT
            TELEGRAM_CHAT_ID=${INPUT_TG_CHAT:-${SAVED_TELEGRAM_CHAT_ID:-}}
            if [ -n "${TELEGRAM_BOT_TOKEN}" ] && [ -n "${TELEGRAM_CHAT_ID}" ]; then
                log_ok "Telegram-оповещения настроены"
            else
                log_warn "Токен или Chat ID не заполнены, оповещения отключены"
                ENABLE_TELEGRAM="N"
            fi
        else
            ENABLE_TELEGRAM="N"
            TELEGRAM_BOT_TOKEN=""
            TELEGRAM_CHAT_ID=""
        fi
    fi

    SHARE_NAME=$(basename "${SAVE_DIR}" | tr -cd '[:alnum:]_-')
    [ -z "${SHARE_NAME}" ] && SHARE_NAME="storage"

    local ROOT_DEV
    ROOT_DEV=$(df -P / 2>/dev/null | awk 'NR==2{print $1}' || echo "/dev/root")
    local SAVE_DEV
    SAVE_DEV=$(df -P "${SAVE_DIR}" 2>/dev/null | awk 'NR==2{print $1}' || echo "${ROOT_DEV}")

    if [ "${ROOT_DEV}" != "${SAVE_DEV}" ] || [ -n "${STORAGE_DEP_LINE}" ]; then
        VAULT_DATA_DIR="${SAVE_DIR}/services/vaultwarden"
        GITEA_DATA_DIR="${SAVE_DIR}/services/gitea"
        ADGUARD_WORK_DIR="${SAVE_DIR}/services/adguard_work"
    else
        VAULT_DATA_DIR="${APP_DIR}/vaultwarden"
        GITEA_DATA_DIR="${APP_DIR}/gitea"
        ADGUARD_WORK_DIR="${APP_DIR}/adguard/work"
    fi

    save_configuration
}

setup_credentials() {
    print_step_header "04/11" "ГЕНЕРАЦИЯ КРИПТОГРАФИЧЕСКИХ ХЭШЕЙ"

    modprobe tun 2>/dev/null || true
    mkdir -p /etc/modules-load.d
    echo "tun" > /etc/modules-load.d/tun.conf
    grep -q '^tun$' /etc/modules 2>/dev/null || echo "tun" >> /etc/modules 2>/dev/null || true

    mkdir -p /dev/net
    if [ ! -c /dev/net/tun ]; then
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 666 /dev/net/tun 2>/dev/null || true
    fi

    log_info "Хэширование пароля AdGuard Home (Bcrypt)..."
    AGH_HASH=""
    
    AGH_HASH=$(python3 -c "
import sys, warnings
warnings.simplefilter('ignore')
pw = sys.stdin.read().rstrip('\r\n')
try:
    import bcrypt
    print(bcrypt.hashpw(pw.encode('utf-8'), bcrypt.gensalt(10)).decode('utf-8'))
    sys.exit(0)
except Exception:
    pass
try:
    import passlib.hash
    print(passlib.hash.bcrypt.hash(pw))
    sys.exit(0)
except Exception:
    pass
sys.exit(1)
" <<< "${AGH_PASS}" 2>/dev/null || true)

    if [ -z "${AGH_HASH}" ] && command -v htpasswd >/dev/null 2>&1; then
        AGH_HASH=$(printf '%s\n' "${AGH_PASS}" | htpasswd -B -C 10 -n -i "${ADMIN_USER}" 2>/dev/null | cut -d: -f2 || true)
    fi

    if [ -z "${AGH_HASH}" ] && command -v docker >/dev/null 2>&1; then
        AGH_HASH=$(printf '%s' "${AGH_PASS}" | docker run -i --rm "caddy:alpine" caddy hash-password 2>/dev/null | tr -d '\r\n' || true)
    fi

    if [ -z "${AGH_HASH}" ]; then
        log_err "Критическая ошибка: Не удалось сформировать Bcrypt-хэш пароля для AdGuard Home!"
        exit 1
    else
        log_ok "Bcrypt-хэш для AdGuard Home успешно сформирован"
    fi
    AGH_HASH_CADDY="${AGH_HASH}"

    VAULT_ADMIN_HASH_ESCAPED=""
    if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
        log_info "Хэширование токена Vaultwarden /admin (Argon2id)..."
        local SALT_VAL
        SALT_VAL=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))" 2>/dev/null || echo "homelabdefaults123")
        
        if command -v argon2 >/dev/null 2>&1; then
            VAULT_ADMIN_HASH=$(printf '%s' "${VAULT_ADMIN_TOKEN}" | argon2 "${SALT_VAL}" -e -id -k 65540 -t 3 -p 4 2>/dev/null | grep -E '^\$argon2id' || true)
        fi

        if [ -z "${VAULT_ADMIN_HASH:-}" ] && command -v docker >/dev/null 2>&1; then
            VAULT_ADMIN_HASH=$(printf '%s\n%s\n' "${VAULT_ADMIN_TOKEN}" "${VAULT_ADMIN_TOKEN}" | docker run -i --rm vaultwarden/server:alpine /vaultwarden hash --preset owasp 2>/dev/null | grep -E '^\$argon2id' | tr -d '\r\n' || true)
        fi

        if [ -z "${VAULT_ADMIN_HASH:-}" ]; then
            VAULT_ADMIN_HASH="${VAULT_ADMIN_TOKEN}"
        fi
        VAULT_ADMIN_HASH_ESCAPED="${VAULT_ADMIN_HASH//\$/\$\$}"
    fi
    log_ok "Криптографические хэши сервисов подготовлены"
}
