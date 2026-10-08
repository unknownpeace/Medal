# =============================================================================
# Module: 01_system.sh
# Banner, System Privileges, Hardware & OS Detection, Configuration Loader, NTP
# =============================================================================

show_banner() {
    clear 2>/dev/null || true
    echo -e "${CLR_NEON_CYAN}"
    cat << 'EOF_LOGO'
  ███╗   ███╗███████╗██████╗  █████╗ ██╗     
  ████╗ ████║██╔════╝██╔══██╗██╔══██╗██║     
  ██╔████╔██║█████╗  ██║  ██║███████║██║     
  ██║╚██╔╝██║██╔══╝  ██║  ██║██╔══██║██║     
  ██║ ╚═╝ ██║███████╗██████╔╝██║  ██║███████╗
  ╚═╝     ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚══════╝
EOF_LOGO
    echo -e "${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}╔══════════════════════════════════════════════════════════════════════════╗${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}   ${CLR_WHITE}${CLR_BOLD}HOMELAB APPLIANCE & TRANSPARENT GATEWAY${CLR_RESET} ${CLR_NEON_CYAN}◈${CLR_RESET} ${CLR_NEON_GREEN}${CLR_BOLD}RUSSIA PRO 2026${CLR_RESET}        ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}╠══════════════════════════════════════════════════════════════════════════╣${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}  ${CLR_NEON_CYAN}◆ ПРОЗРАЧНЫЙ СЕТЕВОЙ ШЛЮЗ: MIHOMO TUN + ADGUARD HOME (CLEAN DNS)        ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}                                                                          ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}   ${CLR_WHITE}[ КЛИЕНТЫ LAN ]${CLR_RESET} ──► ${CLR_NEON_CYAN}[ ADGUARD :53 ]${CLR_RESET} ──► ${CLR_NEON_PURPLE}[ MIHOMO TUN :1053 ]${CLR_RESET}                 ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}   (ТВ, ПК, Смартфоны)      CleanDNS/ZeroCache     Fake-IP / Mixed TUN / gVisor    ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}           │                          │                                           ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}           │                          ▼ (Анти-Утечки)   Маршрутизация трафика:    ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}           │                   ${CLR_RED}[ ECH / DOH DROP ]${CLR_RESET}  ├─► ${CLR_NEON_PINK}[ US-AUTO ]${CLR_RESET} ChatGPT / Claude  ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}           │                                            ├─► ${CLR_NEON_GOLD}[ PROXY ]${CLR_RESET} YT, Discord, Блоки  ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}           │                                            └─► ${CLR_NEON_GREEN}[ DIRECT ]${CLR_RESET} РФ / Банки / Steam ║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}           ▼                                                                      ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}   ${CLR_NEON_GREEN}[ ПРЯМОЙ ВЫХОД ]${CLR_RESET} ────────────────────────────────────────────────────────────┘        ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}   • Умный Fake-IP DNS + nftables: Прозрачный обход без настройки клиентов ║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}╠══════════════════════════════════════════════════════════════════════════╣${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}  ${CLR_WHITE}⚡ ЯДРО:${CLR_RESET} ${CLR_CYAN}Mihomo TUN${CLR_RESET} │ ${CLR_CYAN}AdGuard Home${CLR_RESET} │ ${CLR_CYAN}nftables${CLR_RESET} │ ${CLR_CYAN}Caddy SSL${CLR_RESET} │ ${CLR_CYAN}Docker${CLR_RESET}              ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}  ${CLR_WHITE}⚡ ПРИЛОЖЕНИЯ:${CLR_RESET} ${CLR_CYAN}Navidrome (Spotify)${CLR_RESET} │ ${CLR_CYAN}MeTube${CLR_RESET} │ ${CLR_CYAN}Vaultwarden${CLR_RESET} │ ${CLR_CYAN}qBittorrent${CLR_RESET} │ ${CLR_CYAN}Samba NAS${CLR_RESET} │ ${CLR_CYAN}Gitea${CLR_RESET}   ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}  ${CLR_WHITE}⚡ СИСТЕМА:${CLR_RESET} ${CLR_GRAY}Debian • Ubuntu • Arch Linux • Alpine Linux (OpenRC & Systemd)${CLR_RESET}   ${CLR_NEON_PURPLE}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}╚══════════════════════════════════════════════════════════════════════════╝${CLR_RESET}"
    echo ""
}

check_privileges() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_err "Скрипт должен быть запущен с правами root (sudo / doas)!"
        echo -e "      ${CLR_WHITE}Запуск: sudo $0${CLR_RESET}"
        exit 1
    fi
    if [ ! -t 0 ]; then
        { exec < /dev/tty; } 2>/dev/null || true
    fi
}

detect_hardware_capabilities() {
    SYSTEM_ARCH=$(uname -m 2>/dev/null || echo "x86_64")
    HAS_HARDWARE_AES=0
    if grep -q -E '(aes|pmull|armv8-ce)' /proc/cpuinfo 2>/dev/null; then
        HAS_HARDWARE_AES=1
    fi

    IS_CONTAINER=0
    if [ -f /.dockerenv ] || grep -qE '(lxc|docker|kubepods)' /proc/1/cgroup 2>/dev/null || [ -f /run/systemd/container ]; then
        IS_CONTAINER=1
    fi

    local CPU_CORES
    CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
    local RAM_MB
    RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 2048)
    log_info "Аппаратная платформа: ${SYSTEM_ARCH} (${CPU_CORES} CPU, ${RAM_MB} МБ RAM, Аппаратный AES: $([ $HAS_HARDWARE_AES -eq 1 ] && echo "Да" || echo "Нет/Софт")$([ $IS_CONTAINER -eq 1 ] && echo ", Среда: Контейнер/LXC" || echo ""))"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-}"
        OS_ID_LIKE="${ID_LIKE:-}"
        OS_VER_ID="${VERSION_ID:-}"
        OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    else
        log_err "Не удалось определить дистрибутив Linux (/etc/os-release отсутствует)!"
        exit 1
    fi

    DISTRO_FAMILY=""
    if [[ "${OS_ID}" =~ ^(arch|artix|endeavouros|manjaro)$ ]] || [[ "${OS_ID_LIKE}" =~ arch ]]; then
        DISTRO_FAMILY="arch"
        log_ok "Обнаружена ОС семейства Arch Linux: ${CLR_WHITE}${PRETTY_NAME:-Arch Linux}${CLR_RESET}"
    elif [[ "${OS_ID}" =~ ^alpine$ ]] || [[ "${OS_ID_LIKE}" =~ alpine ]]; then
        DISTRO_FAMILY="alpine"
        log_ok "Обнаружена ОС семейства Alpine Linux: ${CLR_WHITE}${PRETTY_NAME:-Alpine Linux} (${OS_VER_ID:-})${CLR_RESET}"
    elif [[ "${OS_ID}" =~ ^debian$ ]] || [[ "${OS_ID_LIKE}" =~ debian && ! "${OS_ID}" =~ ubuntu ]]; then
        DISTRO_FAMILY="debian"
        local DEB_VER="${OS_VER_ID%%.*}"
        if [ -n "${DEB_VER}" ] && [ "${DEB_VER}" -lt 12 ]; then
            log_err "Обнаружена устаревшая версия Debian ${OS_VER_ID} (${OS_CODENAME})!"
            log_err "Требуется Debian 12 (Bookworm) или новее. Рекомендуется Debian 13 (Trixie)."
            exit 1
        elif [ -n "${DEB_VER}" ] && [ "${DEB_VER}" -eq 12 ]; then
            log_warn "Обнаружен Debian 12 (Bookworm). Рекомендуется Debian 13 (Trixie), но установка продолжена в режиме совместимости."
        else
            log_ok "Обнаружена ОС семейства Debian: ${CLR_WHITE}${PRETTY_NAME:-Debian 13 (Trixie)}${CLR_RESET}"
        fi
    elif [[ "${OS_ID}" =~ ^ubuntu$ ]] || [[ "${OS_ID_LIKE}" =~ ubuntu ]]; then
        DISTRO_FAMILY="debian"
        local IS_SUPPORTED_UBU=1
        if command -v dpkg >/dev/null 2>&1; then
            if ! dpkg --compare-versions "${OS_VER_ID:-0}" ge "24.04"; then
                IS_SUPPORTED_UBU=0
            fi
        else
            local UBU_NUM
            UBU_NUM=$(echo "${OS_VER_ID:-0}" | awk '{print ($1 >= 24.04) ? 1 : 0}')
            [ "${UBU_NUM}" -eq 1 ] || IS_SUPPORTED_UBU=0
        fi

        if [ "${IS_SUPPORTED_UBU}" -eq 0 ]; then
            log_err "Обнаружена неподдерживаемая версия Ubuntu ${OS_VER_ID:-} (${OS_CODENAME:-})!"
            log_err "Требуется Ubuntu 24.04 LTS или новее. Рекомендуется Ubuntu 26.04 LTS (Resolute Raccoon)."
            exit 1
        fi
        log_ok "Обнаружена ОС семейства Ubuntu: ${CLR_WHITE}${PRETTY_NAME:-Ubuntu 26.04 LTS (Resolute)}${CLR_RESET}"
    else
        log_err "Неподдерживаемый дистрибутив: ${OS_ID}."
        log_err "Поддерживаются: Debian 13/12, Ubuntu 26.04/24.04 LTS, Arch Linux, Alpine Linux v3.19+."
        exit 1
    fi

    INIT_SYSTEM="systemd"
    if [ "${DISTRO_FAMILY}" = "alpine" ] || [ -f /sbin/openrc-run ] || command -v rc-service >/dev/null 2>&1; then
        if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
            INIT_SYSTEM="openrc"
        fi
    fi
    log_info "Используется подсистема инициализации: ${INIT_SYSTEM}"
}

load_previous_config() {
    if [ -f "${ENV_FILE}" ]; then
        log_info "Обнаружен файл конфигурации с прошлыми настройками. Значения загружены."
        # shellcheck disable=SC1090
        source "${ENV_FILE}"
        if [ -n "${SAVED_MASTER_PASS:-}" ]; then
            MASTER_PASS="${SAVED_MASTER_PASS}"
            MIHOMO_SECRET="${SAVED_MASTER_PASS}"
            SAMBA_PASS="${SAVED_MASTER_PASS}"
            AGH_PASS="${SAVED_MASTER_PASS}"
        fi
        [ -n "${SAVED_SELECTED_DOH_1:-}" ] && SELECTED_DOH_1="${SAVED_SELECTED_DOH_1}"
        [ -n "${SAVED_SELECTED_DOH_2:-}" ] && SELECTED_DOH_2="${SAVED_SELECTED_DOH_2}"
        [ -n "${SAVED_SELECTED_DOH_3:-}" ] && SELECTED_DOH_3="${SAVED_SELECTED_DOH_3}"
        [ -n "${SAVED_SELECTED_DOT_1:-}" ] && SELECTED_DOT_1="${SAVED_SELECTED_DOT_1}"
        [ -n "${SAVED_SELECTED_DOT_2:-}" ] && SELECTED_DOT_2="${SAVED_SELECTED_DOT_2}"
        [ -n "${SAVED_SELECTED_BOOTSTRAP_IPS:-}" ] && SELECTED_BOOTSTRAP_IPS="${SAVED_SELECTED_BOOTSTRAP_IPS}"
        [ -n "${SAVED_SELECTED_BOOTSTRAP_IP_1:-}" ] && SELECTED_BOOTSTRAP_IP_1="${SAVED_SELECTED_BOOTSTRAP_IP_1}"
        [ -n "${SAVED_LOGS_DOMAIN:-}" ] && LOGS_DOMAIN="${SAVED_LOGS_DOMAIN}"
        [ -n "${SAVED_ENABLE_TELEGRAM:-}" ] && ENABLE_TELEGRAM="${SAVED_ENABLE_TELEGRAM}"
        [ -n "${SAVED_TELEGRAM_BOT_TOKEN:-}" ] && TELEGRAM_BOT_TOKEN="${SAVED_TELEGRAM_BOT_TOKEN}"
        [ -n "${SAVED_TELEGRAM_CHAT_ID:-}" ] && TELEGRAM_CHAT_ID="${SAVED_TELEGRAM_CHAT_ID}"
        [ -n "${SAVED_SAVE_FSTYPE:-}" ] && SAVE_FSTYPE="${SAVED_SAVE_FSTYPE}"
        [ -n "${SAVED_HOMELAB_VERSION:-}" ] && CURRENT_INSTALLED_VERSION="${SAVED_HOMELAB_VERSION}"
        [ -n "${SAVED_ADMIN_USER:-}" ] && ADMIN_USER="${SAVED_ADMIN_USER}"
        [ -n "${SAVED_SAVE_DIR:-}" ] && SAVE_DIR="${SAVED_SAVE_DIR}"
        [ -n "${SAVED_STORAGE_MODE:-}" ] && STORAGE_MODE="${SAVED_STORAGE_MODE}"
        [ -n "${SAVED_ENABLE_GATEWAY:-}" ] && ENABLE_GATEWAY="${SAVED_ENABLE_GATEWAY}"
        [ -n "${SAVED_ENABLE_VAULT:-}" ] && ENABLE_VAULT="${SAVED_ENABLE_VAULT}"
        [ -n "${SAVED_ENABLE_GITEA:-}" ] && ENABLE_GITEA="${SAVED_ENABLE_GITEA}"
        [ -n "${SAVED_ENABLE_SAMBA:-}" ] && ENABLE_SAMBA="${SAVED_ENABLE_SAMBA}"
        [ -n "${SAVED_ENABLE_QBIT:-}" ] && ENABLE_QBIT="${SAVED_ENABLE_QBIT}"
        [ -n "${SAVED_ENABLE_METUBE:-}" ] && ENABLE_METUBE="${SAVED_ENABLE_METUBE}"
        [ -n "${SAVED_METUBE_DOMAIN:-}" ] && METUBE_DOMAIN="${SAVED_METUBE_DOMAIN}"
        [ -n "${SAVED_ENABLE_NAVIDROME:-}" ] && ENABLE_NAVIDROME="${SAVED_ENABLE_NAVIDROME}"
        [ -n "${SAVED_MUSIC_DOMAIN:-}" ] && MUSIC_DOMAIN="${SAVED_MUSIC_DOMAIN}"
        [ -n "${SAVED_SSL_MODE:-}" ] && SSL_MODE="${SAVED_SSL_MODE}"
        [ -n "${SAVED_DUCKDNS_NAME:-}" ] && DUCKDNS_NAME="${SAVED_DUCKDNS_NAME}"
        [ -n "${SAVED_DUCKDNS_TOKEN:-}" ] && DUCKDNS_TOKEN="${SAVED_DUCKDNS_TOKEN}"
        [ -n "${SAVED_SUB_URL:-}" ] && SUB_URL="${SAVED_SUB_URL}"
        [ -n "${SAVED_TARGET_USER:-}" ] && TARGET_USER="${SAVED_TARGET_USER}"
        [ -n "${SAVED_SHARE_NAME:-}" ] && SHARE_NAME="${SAVED_SHARE_NAME}"
        [ -n "${SAVED_BASE_DOMAIN:-}" ] && BASE_DOMAIN="${SAVED_BASE_DOMAIN}"
        [ -n "${SAVED_VAULT_DOMAIN:-}" ] && VAULT_DOMAIN="${SAVED_VAULT_DOMAIN}"
        [ -n "${SAVED_GITEA_DOMAIN:-}" ] && GITEA_DOMAIN="${SAVED_GITEA_DOMAIN}"
        [ -n "${SAVED_ADGUARD_DOMAIN:-}" ] && ADGUARD_DOMAIN="${SAVED_ADGUARD_DOMAIN}"
        [ -n "${SAVED_TORRENT_DOMAIN:-}" ] && TORRENT_DOMAIN="${SAVED_TORRENT_DOMAIN}"
        [ -n "${SAVED_PROXY_DOMAIN:-}" ] && PROXY_DOMAIN="${SAVED_PROXY_DOMAIN}"
        [ -n "${SAVED_VAULT_DATA_DIR:-}" ] && VAULT_DATA_DIR="${SAVED_VAULT_DATA_DIR}"
        [ -n "${SAVED_GITEA_DATA_DIR:-}" ] && GITEA_DATA_DIR="${SAVED_GITEA_DATA_DIR}"
        [ -n "${SAVED_ADGUARD_WORK_DIR:-}" ] && ADGUARD_WORK_DIR="${SAVED_ADGUARD_WORK_DIR}"
        [ -n "${SAVED_VAULT_ADMIN_TOKEN:-}" ] && VAULT_ADMIN_TOKEN="${SAVED_VAULT_ADMIN_TOKEN}"
        [ -n "${SAVED_SUBDIR_NAME:-}" ] && SUBDIR_NAME="${SAVED_SUBDIR_NAME}"
    fi
}

sync_time() {
    log_info "Проверка и синхронизация системного времени..."
    local HTTP_DATE=""
    if command -v curl >/dev/null 2>&1; then
        HTTP_DATE=$(curl -sI -m 4 http://yandex.ru 2>/dev/null | grep -i '^date:' | head -n1 | cut -d' ' -f2- | tr -d '\r' || true)
        [ -z "${HTTP_DATE}" ] && HTTP_DATE=$(curl -sI -m 4 http://vk.com 2>/dev/null | grep -i '^date:' | head -n1 | cut -d' ' -f2- | tr -d '\r' || true)
        [ -z "${HTTP_DATE}" ] && HTTP_DATE=$(curl -sI -m 4 http://connectivitycheck.gstatic.com/generate_204 2>/dev/null | grep -i '^date:' | head -n1 | cut -d' ' -f2- | tr -d '\r' || true)
        [ -z "${HTTP_DATE}" ] && HTTP_DATE=$(curl -sI -m 4 http://deb.debian.org 2>/dev/null | grep -i '^date:' | head -n1 | cut -d' ' -f2- | tr -d '\r' || true)
    elif command -v wget >/dev/null 2>&1; then
        HTTP_DATE=$(wget --server-response --spider --timeout=4 http://yandex.ru 2>&1 | grep -i '^[[:space:]]*date:' | head -n1 | sed -e 's/^[[:space:]]*[Dd]ate:[[:space:]]*//' | tr -d '\r' || true)
        [ -z "${HTTP_DATE}" ] && HTTP_DATE=$(wget --server-response --spider --timeout=4 http://deb.debian.org 2>&1 | grep -i '^[[:space:]]*date:' | head -n1 | sed -e 's/^[[:space:]]*[Dd]ate:[[:space:]]*//' | tr -d '\r' || true)
    fi

    if [ -n "${HTTP_DATE}" ]; then
        local ISO_DATE
        ISO_DATE=$(echo "${HTTP_DATE}" | tr -d ',' | awk '
        BEGIN {
            m["Jan"]="01"; m["Feb"]="02"; m["Mar"]="03"; m["Apr"]="04";
            m["May"]="05"; m["Jun"]="06"; m["Jul"]="07"; m["Aug"]="08";
            m["Sep"]="09"; m["Oct"]="10"; m["Nov"]="11"; m["Dec"]="12";
        }
        NF>=5 {
            printf "%s-%s-%02d %s\n", $4, m[$3], $2, $5
        }')
        if [ -n "${ISO_DATE}" ] && date -u -s "${ISO_DATE}" >/dev/null 2>&1; then
            log_ok "Системное время синхронизировано: $(date -R 2>/dev/null || date)"
        elif date -s "${HTTP_DATE}" >/dev/null 2>&1; then
            log_ok "Системное время синхронизировано: $(date -R 2>/dev/null || date)"
        fi
    fi

    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        mkdir -p /etc/systemd/timesyncd.conf.d
        cat << 'EOF_TIMESYNC' > /etc/systemd/timesyncd.conf.d/01-ru-ntp.conf
[Time]
NTP=0.ru.pool.ntp.org 1.ru.pool.ntp.org ntp.ru pool.ntp.org
FallbackNTP=time.cloudflare.com time.google.com
EOF_TIMESYNC
        if command -v timedatectl >/dev/null 2>&1; then
            timedatectl set-ntp true 2>/dev/null || true
        fi

        if systemctl is-active --quiet systemd-timesyncd 2>/dev/null || systemctl list-unit-files 2>/dev/null | grep -q 'systemd-timesyncd'; then
            systemctl unmask systemd-timesyncd 2>/dev/null || true
            systemctl restart systemd-timesyncd >/dev/null 2>&1 || systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
        fi
    elif [ "${INIT_SYSTEM}" = "openrc" ]; then
        if command -v chronyd >/dev/null 2>&1; then
            rc-update add chronyd default >/dev/null 2>&1 || true
            rc-service chronyd start >/dev/null 2>&1 || true
        elif command -v ntpd >/dev/null 2>&1; then
            rc-update add ntpd default >/dev/null 2>&1 || true
            rc-service ntpd start >/dev/null 2>&1 || true
        fi
    fi
}
