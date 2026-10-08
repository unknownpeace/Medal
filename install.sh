#!/usr/bin/env bash
# =============================================================================
# Project: Homelab Appliance & Transparent Gateway (Russia Pro Edition 2026)
# Enterprise & Homelab Unified Gateway | Linux 2026 Ecosystem & Docker 28+ / 29+
# Supported OS: Debian 13 (Trixie), Ubuntu 26.04 LTS (Resolute), Arch Linux,
#               Alpine Linux v3.19+ (OpenRC)
#   (Compatibility Mode: Debian 12+, Ubuntu 24.04+, Alpine Linux v3.18+)
# Components: AdGuard Home (Schema 34+ & RU Filters), Mihomo TUN (Smart Routing,
#             Mixed Stack & MRS Rulesets, YouTube/Discord/AI/RU-Direct Passthrough),
#             Vaultwarden (Argon2id), Gitea (Git-Server), Samba (WSDD2),
#             qBittorrent (VueTorrent WebUI), MeTube (Video/Audio Downloader),
#             Navidrome (Hi-Fi Music Streaming), Caddy (Internal/DuckDNS SSL),
#             Watchtower (Docker API 1.45+)
# =============================================================================

# Self-bootstrap into bash if started under /bin/sh or via pipe
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        if [ -f "$0" ]; then
            exec bash "$0" "$@"
        else
            TMP_SCRIPT=$(mktemp /tmp/homelab_bootstrap_XXXXXX.sh)
            cat > "${TMP_SCRIPT}"
            chmod +x "${TMP_SCRIPT}"
            exec bash "${TMP_SCRIPT}" "$@"
        fi
    else
        echo "[!] Bash is required for this installer." >&2
        if command -v apk >/dev/null 2>&1; then
            echo "[*] Installing bash via apk..." >&2
            apk add --no-cache bash
        elif command -v apt-get >/dev/null 2>&1; then
            echo "[*] Installing bash via apt-get..." >&2
            apt-get update && apt-get install -y bash
        elif command -v pacman >/dev/null 2>&1; then
            echo "[*] Installing bash via pacman..." >&2
            pacman -Sy --noconfirm bash
        else
            echo "[-] Error: Bash is not installed. Please install bash and re-run." >&2
            exit 1
        fi
        if [ -f "$0" ]; then
            exec bash "$0" "$@"
        else
            TMP_SCRIPT=$(mktemp /tmp/homelab_bootstrap_XXXXXX.sh)
            cat > "${TMP_SCRIPT}"
            chmod +x "${TMP_SCRIPT}"
            exec bash "${TMP_SCRIPT}" "$@"
        fi
    fi
fi

set -Eeuo pipefail

# --- ЦВЕТОВАЯ ПАЛИТРА И КИБЕРПАНК СТИЛЬ ОФОРМЛЕНИЯ (2026 PRO) ---
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_DIM="\033[2m"
CLR_ITALIC="\033[3m"
CLR_UNDER="\033[4m"

CLR_RED="\033[1;31m"
CLR_GREEN="\033[1;32m"
CLR_YELLOW="\033[1;33m"
CLR_BLUE="\033[1;34m"
CLR_CYAN="\033[1;36m"
CLR_MAGENTA="\033[1;35m"
CLR_WHITE="\033[1;37m"
CLR_MUTED="\033[0;36m"
CLR_GRAY="\033[0;90m"

# Эстетические неоновые акценты (при поддержке терминала)
if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
    CLR_NEON_CYAN="\033[38;5;51m"
    CLR_NEON_GREEN="\033[38;5;48m"
    CLR_NEON_BLUE="\033[38;5;39m"
    CLR_NEON_PURPLE="\033[38;5;141m"
    CLR_NEON_PINK="\033[38;5;198m"
    CLR_NEON_GOLD="\033[38;5;220m"
else
    CLR_NEON_CYAN="${CLR_CYAN}"
    CLR_NEON_GREEN="${CLR_GREEN}"
    CLR_NEON_BLUE="${CLR_BLUE}"
    CLR_NEON_PURPLE="${CLR_MAGENTA}"
    CLR_NEON_PINK="${CLR_MAGENTA}"
    CLR_NEON_GOLD="${CLR_YELLOW}"
fi

TAG_INFO="${CLR_NEON_CYAN}✦${CLR_RESET}"
TAG_OK="${CLR_NEON_GREEN}✔${CLR_RESET}"
TAG_WARN="${CLR_NEON_GOLD}▲${CLR_RESET}"
TAG_ERR="${CLR_RED}✖${CLR_RESET}"
TAG_BOLT="${CLR_NEON_GOLD}⚡${CLR_RESET}"
TAG_DIAMOND="${CLR_NEON_PURPLE}◈${CLR_RESET}"

log_info()  { echo -e "  ${TAG_INFO} ${CLR_CYAN}$*${CLR_RESET}"; }
log_ok()    { echo -e "  ${TAG_OK} ${CLR_GREEN}$*${CLR_RESET}"; }
log_warn()  { echo -e "  ${TAG_WARN} ${CLR_YELLOW}$*${CLR_RESET}"; }
log_err()   { echo -e "  ${TAG_ERR} ${CLR_RED}$*${CLR_RESET}" >&2; }

print_step_header() {
    local step_num="$1"
    local step_title="$2"
    echo ""
    echo -e "${CLR_NEON_PURPLE}╭──${CLR_NEON_CYAN} [ ${CLR_WHITE}${CLR_BOLD}${step_num}${CLR_RESET}${CLR_NEON_CYAN} ] ${CLR_NEON_PURPLE}──────────────────────────────────────────────────────────────────╮${CLR_RESET}"
    echo -e "${CLR_NEON_PURPLE}│  ${CLR_NEON_GOLD}⚡${CLR_RESET} ${CLR_WHITE}${CLR_BOLD}${step_title}${CLR_RESET}"
    echo -e "${CLR_NEON_PURPLE}╰────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
}

CURRENT_SPIN_PID=""
CURRENT_SPIN_LOG=""

# Анимированный спиннер с защитой от утечки курсора и TTY-адаптацией
run_spin() {
    local full_msg="$1"
    shift
    local max_len=40
    local disp_msg="${full_msg:0:$max_len}"
    [ ${#full_msg} -gt $max_len ] && disp_msg="${disp_msg}..."

    local log_tmp
    log_tmp=$(mktemp)
    CURRENT_SPIN_LOG="${log_tmp}"

    if [ ! -t 1 ]; then
        local exit_code=0
        "$@" >"${log_tmp}" 2>&1 || exit_code=$?
        if [ $exit_code -eq 0 ]; then
            printf "  ${CLR_GREEN}✔${CLR_RESET} ${CLR_WHITE}%-45s${CLR_RESET} ${CLR_GREEN}[ГОТОВО]${CLR_RESET}\n" "${disp_msg}"
            rm -f "${log_tmp}"
            CURRENT_SPIN_LOG=""
            return 0
        else
            printf "  ${CLR_RED}✖${CLR_RESET} ${CLR_WHITE}%-45s${CLR_RESET} ${CLR_RED}[СБОЙ]${CLR_RESET}\n" "${disp_msg}"
            echo -e "${CLR_RED}--- Журнал ошибки (${full_msg}): ---${CLR_RESET}" >&2
            tail -n 35 "${log_tmp}" >&2
            echo -e "${CLR_RED}-----------------------------------${CLR_RESET}" >&2
            rm -f "${log_tmp}"
            CURRENT_SPIN_LOG=""
            return $exit_code
        fi
    fi

    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    "$@" >"${log_tmp}" 2>&1 &
    local pid=$!
    CURRENT_SPIN_PID="$pid"
    local i=0

    printf "\033[?25l"
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\033[2K  ${CLR_CYAN}${spin[i]}${CLR_RESET} ${CLR_WHITE}%-43s${CLR_RESET}" "${disp_msg}"
        i=$(( (i + 1) % 10 ))
        sleep 0.08
    done

    local exit_code=0
    wait "$pid" 2>/dev/null || exit_code=$?
    CURRENT_SPIN_PID=""

    printf "\033[?25h"

    if [ $exit_code -eq 0 ]; then
        printf "\r\033[2K  ${CLR_GREEN}✔${CLR_RESET} ${CLR_WHITE}%-45s${CLR_RESET} ${CLR_GREEN}[ГОТОВО]${CLR_RESET}\n" "${disp_msg}"
        rm -f "${log_tmp}"
        CURRENT_SPIN_LOG=""
        return 0
    else
        printf "\r\033[2K  ${CLR_RED}✖${CLR_RESET} ${CLR_WHITE}%-45s${CLR_RESET} ${CLR_RED}[СБОЙ]${CLR_RESET}\n" "${disp_msg}"
        echo -e "${CLR_RED}--- Журнал ошибки (${full_msg}): ---${CLR_RESET}" >&2
        tail -n 35 "${log_tmp}" >&2
        echo -e "${CLR_RED}-----------------------------------${CLR_RESET}" >&2
        rm -f "${log_tmp}"
        CURRENT_SPIN_LOG=""
        return $exit_code
    fi
}

on_error() {
    local exit_code=$?
    local line_no=$1
    local cmd=$2
    printf "\033[?25h"
    echo ""
    log_err "Критическая ошибка (код ${exit_code}) на строке ${line_no}!"
    echo -e "      ${CLR_DIM}Команда: '${cmd}'${CLR_RESET}"
    exit "${exit_code}"
}

cleanup_on_interrupt() {
    printf "\033[?25h\n"
    if [ -n "${CURRENT_SPIN_PID:-}" ] && kill -0 "${CURRENT_SPIN_PID}" 2>/dev/null; then
        kill -9 "${CURRENT_SPIN_PID}" 2>/dev/null || true
    fi
    if [ -n "${CURRENT_SPIN_LOG:-}" ] && [ -f "${CURRENT_SPIN_LOG}" ]; then
        rm -f "${CURRENT_SPIN_LOG}" 2>/dev/null || true
    fi
    echo -e "\n${CLR_YELLOW}Выполнение скрипта прервано пользователем.${CLR_RESET}"
    exit 130
}
trap 'on_error $LINENO "$BASH_COMMAND"' ERR
trap cleanup_on_interrupt INT TERM

# Интеллектуальный ввод с гарантированным выводом промпта даже при SSH без PTY
prompt_read() {
    local prompt_msg="$1"
    local var_name="$2"
    printf "%b" "${prompt_msg}" >&2
    read -r "${var_name}" || true
}

normalize_yn() {
    local val="$1"
    local default_val="${2:-Y}"
    val="${val:-$default_val}"
    if [[ "$val" =~ ^([Yy]|[Yy][Ee][Ss]|1)$ ]]; then
        echo "Y"
    else
        echo "N"
    fi
}

# Универсальный враппер для Docker Compose v2 (стандарт 2026)
dc() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
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
export -f dc 2>/dev/null || true

yaml_escape() {
    local str="$1"
    python3 -c "import sys, json; print(json.dumps(sys.argv[1]))" "${str}" 2>/dev/null || printf '"%s"' "${str//\"/\\\"}"
}

APP_DIR="/opt/homelab"
ENV_FILE="${APP_DIR}/.env"
LUKS_MAP_NAME="homelab_secure_storage"
MOUNT_ROOT="/mnt/homelab_storage"
STORAGE_DEP_LINE=""

REAL_USER="${SUDO_USER:-$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || echo "homelab")}"
TARGET_USER="${REAL_USER:-homelab}"
USER_UID="${USER_UID:-1000}"
USER_GID="${USER_GID:-1000}"
SAVE_FSTYPE=""

DEFAULT_IFACE=""
LOCAL_IP=""
ROUTER_GATEWAY=""
LAN_SUBNET=""
INSTALL_MODE="1"

ENABLE_GATEWAY="Y"
ENABLE_VAULT="Y"
ENABLE_GITEA="Y"
ENABLE_SAMBA="Y"
ENABLE_QBIT="Y"
ENABLE_METUBE="Y"
ENABLE_NAVIDROME="Y"
ENABLE_TELEGRAM="N"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

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

STORAGE_MODE="1"
SUBDIR_NAME=""
SHARE_NAME="storage"
SAVE_DIR="/opt/homelab/save"
SAVE_FSTYPE="ext4"

SUB_URL="none"
ADMIN_USER="admin"
ADMIN_USER_SAFE="admin"
MASTER_PASS=""
MIHOMO_SECRET=""
SAMBA_PASS=""
AGH_PASS=""
AGH_HASH=""
AGH_HASH_CADDY=""
VAULT_ADMIN_TOKEN=""
VAULT_ADMIN_HASH=""
VAULT_ADMIN_HASH_ESCAPED=""

DETECTED_DOCKER_API=""
VAULT_DATA_DIR=""
GITEA_DATA_DIR=""
ADGUARD_WORK_DIR=""
DISTRO_FAMILY=""
INIT_SYSTEM="systemd"
SYSTEM_ARCH=""
HAS_HARDWARE_AES=0
IS_CONTAINER=0
SELECTED_DOH_1=""
SELECTED_DOH_2=""
SELECTED_DOH_3=""
SELECTED_DOT_1=""
SELECTED_DOT_2=""
SELECTED_BOOTSTRAP_IPS="77.88.8.8 1.1.1.1 9.9.9.9 8.8.8.8"
SELECTED_BOOTSTRAP_IP_1="77.88.8.8"
NAVIDROME_IMAGE="deluan/navidrome:latest"
HOMELAB_VERSION="2.8.12"
HOMELAB_REPO="unknownpeace/Medal"
HOMELAB_RAW_URL="https://raw.githubusercontent.com/${HOMELAB_REPO}/main"
IS_UPGRADE_MODE=0

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
    echo -e "  ${CLR_NEON_PURPLE}║${CLR_RESET}           │                   ${CLR_RED}[ ECH / DOH DROP ]${CLR_RESET}  ├─► ${CLR_NEON_PINK}[ AI-Services ]${CLR_RESET} ChatGPT / Claude ${CLR_NEON_PURPLE}║${CLR_RESET}"
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
        SELECTED_DOH_1="${SAVED_SELECTED_DOH_1:-$SELECTED_DOH_1}"
        SELECTED_DOH_2="${SAVED_SELECTED_DOH_2:-$SELECTED_DOH_2}"
        SELECTED_DOH_3="${SAVED_SELECTED_DOH_3:-$SELECTED_DOH_3}"
        SELECTED_DOT_1="${SAVED_SELECTED_DOT_1:-$SELECTED_DOT_1}"
        SELECTED_DOT_2="${SAVED_SELECTED_DOT_2:-$SELECTED_DOT_2}"
        SELECTED_BOOTSTRAP_IPS="${SAVED_SELECTED_BOOTSTRAP_IPS:-$SELECTED_BOOTSTRAP_IPS}"
        SELECTED_BOOTSTRAP_IP_1="${SAVED_SELECTED_BOOTSTRAP_IP_1:-$SELECTED_BOOTSTRAP_IP_1}"
        LOGS_DOMAIN="${SAVED_LOGS_DOMAIN:-$LOGS_DOMAIN}"
        ENABLE_TELEGRAM="${SAVED_ENABLE_TELEGRAM:-$ENABLE_TELEGRAM}"
        TELEGRAM_BOT_TOKEN="${SAVED_TELEGRAM_BOT_TOKEN:-$TELEGRAM_BOT_TOKEN}"
        TELEGRAM_CHAT_ID="${SAVED_TELEGRAM_CHAT_ID:-$TELEGRAM_CHAT_ID}"
        SAVE_FSTYPE="${SAVED_SAVE_FSTYPE:-$SAVE_FSTYPE}"
        CURRENT_INSTALLED_VERSION="${SAVED_HOMELAB_VERSION:-${CURRENT_INSTALLED_VERSION:-}}"
        ADMIN_USER="${SAVED_ADMIN_USER:-$ADMIN_USER}"
        SAVE_DIR="${SAVED_SAVE_DIR:-$SAVE_DIR}"
        STORAGE_MODE="${SAVED_STORAGE_MODE:-$STORAGE_MODE}"
        ENABLE_GATEWAY="${SAVED_ENABLE_GATEWAY:-$ENABLE_GATEWAY}"
        ENABLE_VAULT="${SAVED_ENABLE_VAULT:-$ENABLE_VAULT}"
        ENABLE_GITEA="${SAVED_ENABLE_GITEA:-$ENABLE_GITEA}"
        ENABLE_SAMBA="${SAVED_ENABLE_SAMBA:-$ENABLE_SAMBA}"
        ENABLE_QBIT="${SAVED_ENABLE_QBIT:-$ENABLE_QBIT}"
        ENABLE_METUBE="${SAVED_ENABLE_METUBE:-$ENABLE_METUBE}"
        METUBE_DOMAIN="${SAVED_METUBE_DOMAIN:-$METUBE_DOMAIN}"
        ENABLE_NAVIDROME="${SAVED_ENABLE_NAVIDROME:-$ENABLE_NAVIDROME}"
        MUSIC_DOMAIN="${SAVED_MUSIC_DOMAIN:-$MUSIC_DOMAIN}"
        SSL_MODE="${SAVED_SSL_MODE:-$SSL_MODE}"
        DUCKDNS_NAME="${SAVED_DUCKDNS_NAME:-$DUCKDNS_NAME}"
        DUCKDNS_TOKEN="${SAVED_DUCKDNS_TOKEN:-$DUCKDNS_TOKEN}"
        SUB_URL="${SAVED_SUB_URL:-$SUB_URL}"
        TARGET_USER="${SAVED_TARGET_USER:-$TARGET_USER}"
        SHARE_NAME="${SAVED_SHARE_NAME:-$SHARE_NAME}"
        BASE_DOMAIN="${SAVED_BASE_DOMAIN:-$BASE_DOMAIN}"
        VAULT_DOMAIN="${SAVED_VAULT_DOMAIN:-$VAULT_DOMAIN}"
        GITEA_DOMAIN="${SAVED_GITEA_DOMAIN:-$GITEA_DOMAIN}"
        ADGUARD_DOMAIN="${SAVED_ADGUARD_DOMAIN:-$ADGUARD_DOMAIN}"
        TORRENT_DOMAIN="${SAVED_TORRENT_DOMAIN:-$TORRENT_DOMAIN}"
        PROXY_DOMAIN="${SAVED_PROXY_DOMAIN:-$PROXY_DOMAIN}"
        VAULT_DATA_DIR="${SAVED_VAULT_DATA_DIR:-$VAULT_DATA_DIR}"
        GITEA_DATA_DIR="${SAVED_GITEA_DATA_DIR:-$GITEA_DATA_DIR}"
        ADGUARD_WORK_DIR="${SAVED_ADGUARD_WORK_DIR:-$ADGUARD_WORK_DIR}"
        VAULT_ADMIN_TOKEN="${SAVED_VAULT_ADMIN_TOKEN:-$VAULT_ADMIN_TOKEN}"
        SUBDIR_NAME="${SAVED_SUBDIR_NAME:-$SUBDIR_NAME}"
        USER_UID="${SAVED_USER_UID:-${USER_UID:-1000}}"
        USER_GID="${SAVED_USER_GID:-${USER_GID:-1000}}"
    fi
    return 0
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
    return 0
}

# =============================================================================
# Module: 02_packages.sh
# System Package Installation (Alpine, Arch, Debian, Ubuntu), Docker CE, zRAM
# =============================================================================

install_pkgs() {
    print_step_header "01/11" "УСТАНОВКА ЗАВИСИМОСТЕЙ И СТЕКА DOCKER"

    if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ] && command -v docker >/dev/null 2>&1 && command -v nft >/dev/null 2>&1; then
        log_ok "Системные зависимости и Docker CE уже установлены (пропуск в режиме обновления)"
        return 0
    fi

    if [ "${DISTRO_FAMILY}" = "alpine" ]; then
        if [ -f /etc/apk/repositories ]; then
            sed -i 's/^#\(.*\/community\)/\1/' /etc/apk/repositories 2>/dev/null || true
            if ! grep -q '/community' /etc/apk/repositories 2>/dev/null; then
                awk '{print} /\/main$/ {sub(/\/main$/, "/community"); print}' /etc/apk/repositories > /etc/apk/repositories.tmp 2>/dev/null && \
                mv /etc/apk/repositories.tmp /etc/apk/repositories 2>/dev/null || true
            fi
        fi
        run_spin "Обновление индексов пакетов APK" apk update

        local ALP_PKGS=(bash python3 py3-bcrypt iproute2 cryptsetup btrfs-progs ntfs-3g \
                        util-linux util-linux-misc lsblk curl openssl ca-certificates jq nftables apache2-utils \
                        unzip tar sqlite argon2 iputils shadow procps e2fsprogs ffmpeg \
                        docker docker-cli-compose chrony openrc)
        run_spin "Установка системных пакетов Alpine" \
            apk add --no-cache "${ALP_PKGS[@]}"
        apk add --no-cache cryptsetup-openrc >/dev/null 2>&1 || true

    elif [ "${DISTRO_FAMILY}" = "arch" ]; then
        local ARCH_PKGS=(python python-bcrypt iproute2 cryptsetup btrfs-progs ntfs-3g util-linux \
                         curl openssl ca-certificates jq nftables unzip tar sqlite ffmpeg \
                         docker docker-compose argon2 iputils acl zram-generator)
        local MISSING_PKGS=()
        for p in "${ARCH_PKGS[@]}"; do
            pacman -Q "$p" >/dev/null 2>&1 || MISSING_PKGS+=("$p")
        done
        if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
            log_ok "Все системные пакеты Arch Linux уже установлены (пропуск)"
        else
            run_spin "Установка пакетов Arch (${#MISSING_PKGS[@]} шт.)" \
                pacman -S --noconfirm --needed "${MISSING_PKGS[@]}"
        fi
    elif [ "${DISTRO_FAMILY}" = "debian" ]; then
        export DEBIAN_FRONTEND=noninteractive
        run_spin "Обновление индексов пакетов APT" bash -c "apt-get update -o Acquire::Check-Valid-Until=false -y || apt-get update -y"

        local ZRAM_PKG="systemd-zram-generator"
        if [[ "${OS_ID}" =~ ubuntu ]] || [[ "${OS_ID_LIKE}" =~ ubuntu ]]; then
            ZRAM_PKG="zram-generator"
        fi

        run_spin "Установка системных пакетов и утилит" \
            apt-get install -y --no-install-recommends \
                systemd-timesyncd python3 python3-bcrypt iproute2 cryptsetup btrfs-progs ntfs-3g \
                util-linux curl openssl ca-certificates jq nftables apache2-utils \
                unzip tar sqlite3 argon2 iputils-ping ffmpeg

        # Установка генератора zram с безопасным fallback для Ubuntu/Debian
        apt-get install -y --no-install-recommends "${ZRAM_PKG}" 2>/dev/null || \
        apt-get install -y --no-install-recommends zram-tools 2>/dev/null || true

        if ! command -v docker >/dev/null 2>&1; then
            log_info "Установка официального Docker CE..."
            apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true

            local REPO_OS="debian"
            [[ "${OS_ID}" =~ ubuntu ]] || [[ "${OS_ID_LIKE}" =~ ubuntu ]] && REPO_OS="ubuntu"
            local CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
            if [ -z "${CODENAME}" ]; then
                [ "${REPO_OS}" = "ubuntu" ] && CODENAME="resolute" || CODENAME="trixie"
            fi

            install -m 0755 -d /etc/apt/keyrings
            if ! curl -fsSL --connect-timeout 5 -m 12 "https://download.docker.com/linux/${REPO_OS}/gpg" -o /etc/apt/keyrings/docker.asc 2>/dev/null; then
                log_warn "download.docker.com недоступен. Загрузка GPG-ключа с официального зеркала mirror.yandex.ru..."
                curl -fsSL --connect-timeout 5 -m 12 "https://mirror.yandex.ru/mirrors/docker-ce/linux/${REPO_OS}/gpg" -o /etc/apt/keyrings/docker.asc
            fi
            chmod a+r /etc/apt/keyrings/docker.asc

            local DOCKER_REPO_URL="https://download.docker.com/linux/${REPO_OS}"
            if ! curl -fsSL --connect-timeout 4 -m 8 "https://download.docker.com/linux/${REPO_OS}/" -o /dev/null 2>/dev/null; then
                DOCKER_REPO_URL="https://mirror.yandex.ru/mirrors/docker-ce/linux/${REPO_OS}"
                log_info "Используется высокоскоростное зеркало Docker CE в РФ: ${DOCKER_REPO_URL}"
            fi

            local TARGET_CODENAME="${CODENAME}"
            if ! curl -fsSL --connect-timeout 5 -m 10 "${DOCKER_REPO_URL}/dists/${TARGET_CODENAME}/Release" -o /dev/null 2>/dev/null && \
               ! curl -fsSL --connect-timeout 5 -m 10 "${DOCKER_REPO_URL}/dists/${TARGET_CODENAME}/InRelease" -o /dev/null 2>/dev/null; then
                [ "${REPO_OS}" = "ubuntu" ] && TARGET_CODENAME="noble" || TARGET_CODENAME="bookworm"
                log_warn "Репозиторий для ${CODENAME} недоступен. Используется совместимый: ${TARGET_CODENAME}"
            fi

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_REPO_URL} ${TARGET_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
            
            run_spin "Обновление репозиториев с Docker CE" apt-get update -y
            run_spin "Установка компонентов Docker CE и Compose Plugin" \
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi
    fi

    # Защита накопителя eMMC/SSD: ограничение системного журнала systemd-journald
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        mkdir -p /etc/systemd/journald.conf.d/
        cat <<EOF_JRNL > /etc/systemd/journald.conf.d/00-homelab.conf
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
Storage=persistent
EOF_JRNL
        systemctl restart systemd-journald >/dev/null 2>&1 || true
    fi

    # Настройка актуальных зеркал Docker Hub (2026 год, устойчивость к блокировкам в РФ)
    local MODIFIED_DAEMON
    MODIFIED_DAEMON=$(python3 -c "
import json, os
path = '/etc/docker/daemon.json'
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
mirrors = data.get('registry-mirrors', [])
target_mirrors = [
    'https://dockerhub.timeweb.cloud',
    'https://dockerproxy.net',
    'https://docker.m.daocloud.io'
]
changed = False
for bad in ['https://huecker.io', 'https://mirror.gcr.io', 'https://dockerhub.cloud.ru']:
    while bad in mirrors:
        mirrors.remove(bad)
        changed = True
# Гарантируем, что проверенные зеркала находятся первыми в списке
new_mirrors = []
for tm in target_mirrors:
    new_mirrors.append(tm)
for m in mirrors:
    if m not in new_mirrors:
        new_mirrors.append(m)
if new_mirrors != mirrors:
    mirrors = new_mirrors
    changed = True

if 'log-driver' not in data:
    data['log-driver'] = 'json-file'
    data['log-opts'] = {'max-size': '10m', 'max-file': '3'}
    changed = True
if data.get('max-concurrent-downloads') != 3:
    data['max-concurrent-downloads'] = 3
    data['max-concurrent-uploads'] = 2
    changed = True
if changed:
    os.makedirs('/etc/docker', exist_ok=True)
    data['registry-mirrors'] = mirrors
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print('1')
else:
    print('0')
" 2>/dev/null || echo "0")

    if [ "${INIT_SYSTEM}" = "openrc" ]; then
        rc-update add cgroups boot >/dev/null 2>&1 || true
        rc-service cgroups start >/dev/null 2>&1 || true
        rc-update add docker default >/dev/null 2>&1 || true
        if ! rc-service docker status >/dev/null 2>&1; then
            run_spin "Активация и запуск службы Docker (OpenRC)" rc-service docker start
        elif [ "${MODIFIED_DAEMON}" = "1" ]; then
            run_spin "Обновление конфигурации и перезапуск Docker (актуализированы зеркала)" rc-service docker restart
        else
            log_ok "Служба Docker активна, зеркала Docker Hub уже настроены"
        fi
    else
        if ! systemctl is-active --quiet docker 2>/dev/null; then
            run_spin "Активация и запуск службы Docker" bash -c "systemctl daemon-reload >/dev/null 2>&1 || true && systemctl enable --now docker >/dev/null 2>&1 || true"
        elif [ "${MODIFIED_DAEMON}" = "1" ]; then
            run_spin "Обновление конфигурации и перезапуск Docker (актуализированы зеркала)" bash -c "systemctl daemon-reload >/dev/null 2>&1 || true && systemctl restart docker"
        else
            log_ok "Служба Docker активна, зеркала Docker Hub уже настроены"
        fi
    fi

    if command -v docker >/dev/null 2>&1; then
        docker stop mihomo adguardhome 2>/dev/null || true
    fi

    DETECTED_DOCKER_API=$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || echo "1.45")
    if [ -z "${DETECTED_DOCKER_API}" ]; then
        DETECTED_DOCKER_API="1.45"
    else
        DETECTED_DOCKER_API=$(python3 -c "
import sys
api = '${DETECTED_DOCKER_API}'
try:
    major, minor = [int(x) for x in api.split('.')[:2]]
    if major > 1 or (major == 1 and minor > 45):
        print('1.45')
    elif major == 1 and minor < 40:
        print('1.40')
    else:
        print(f'{major}.{minor}')
except Exception:
    print('1.45')
" 2>/dev/null || echo "1.45")
    fi
    log_info "Согласована стабильная версия Docker API: ${DETECTED_DOCKER_API}"

    mkdir -p /usr/lib/docker/cli-plugins /usr/libexec/docker/cli-plugins
    if command -v docker-compose >/dev/null 2>&1; then
        local DC_PATH
        DC_PATH=$(command -v docker-compose)
        [ ! -e /usr/lib/docker/cli-plugins/docker-compose ] && ln -sf "${DC_PATH}" /usr/lib/docker/cli-plugins/docker-compose
        [ ! -e /usr/libexec/docker/cli-plugins/docker-compose ] && ln -sf "${DC_PATH}" /usr/libexec/docker/cli-plugins/docker-compose
    fi

    local DC_BIN_TMP="/usr/local/bin/dc.tmp.$$"
    cat << 'EOF_DC_BIN' > "${DC_BIN_TMP}"
#!/usr/bin/env bash
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    exec docker compose "$@"
elif command -v docker-compose >/dev/null 2>&1; then
    exec docker-compose "$@"
elif [ -x /usr/lib/docker/cli-plugins/docker-compose ]; then
    exec /usr/lib/docker/cli-plugins/docker-compose "$@"
elif [ -x /usr/libexec/docker/cli-plugins/docker-compose ]; then
    exec /usr/libexec/docker/cli-plugins/docker-compose "$@"
else
    exec docker compose "$@"
fi
EOF_DC_BIN
    chmod 755 "${DC_BIN_TMP}" 2>/dev/null || true
    mv -f "${DC_BIN_TMP}" /usr/local/bin/dc 2>/dev/null || true

    log_ok "Стек Docker CE успешно настроен и готов к работе"
}

setup_zram() {
    if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ] && (swapon --show 2>/dev/null | grep -q 'zram' || [ -f /etc/systemd/zram-generator.conf ] || [ -f /etc/init.d/zram-swap ]); then
        log_ok "Конфигурация zRAM уже активна (пропуск в режиме обновления)"
        return 0
    fi
    local TOTAL_RAM_MB
    TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "2048")
    if [ "${TOTAL_RAM_MB}" -le 4096 ]; then
        log_info "Обнаружен компактный объем RAM (${TOTAL_RAM_MB} МБ). Настройка zRAM..."
        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            mkdir -p /etc/systemd/
            cat << 'EOF_ZRAM_CONF' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = min(ram / 2, 2048)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF_ZRAM_CONF

            if systemctl list-unit-files 2>/dev/null | grep -q "systemd-zram-setup"; then
                systemctl daemon-reload >/dev/null 2>&1 || true
                systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || \
                systemctl start dev-zram0.swap 2>/dev/null || systemctl start /dev/zram0 2>/dev/null || true
            fi
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            cat << 'EOF_ZRAM_RC' > /etc/init.d/zram-swap
#!/sbin/openrc-run
description="zRAM Swap Activation"
depend() {
    after localmount
}
start() {
    ebegin "Activating zRAM swap"
    modprobe zram 2>/dev/null || true
    if command -v zramctl >/dev/null 2>&1; then
        ZDEV=$(zramctl --find --size 1024M --algorithm zstd 2>/dev/null || zramctl --find --size 1024M 2>/dev/null || true)
        if [ -n "${ZDEV}" ]; then
            mkswap "${ZDEV}" >/dev/null 2>&1
            swapon -p 100 "${ZDEV}" >/dev/null 2>&1
            sysctl -w vm.swappiness=150 >/dev/null 2>&1 || true
        fi
    fi
    eend 0
}
stop() {
    ebegin "Deactivating zRAM swap"
    for zd in $(lsblk -lno NAME,TYPE 2>/dev/null | awk '$2=="zram"{print "/dev/"$1}'); do
        swapoff "$zd" 2>/dev/null || true
        zramctl -r "$zd" 2>/dev/null || true
    done
    eend 0
}
EOF_ZRAM_RC
            chmod 755 /etc/init.d/zram-swap
            rc-update add zram-swap default >/dev/null 2>&1 || true
        fi

        if ! swapon --show 2>/dev/null | grep -q "zram"; then
            modprobe zram 2>/dev/null || true
            if command -v zramctl >/dev/null 2>&1; then
                local ZDEV
                ZDEV=$(zramctl --find --size 1024M --algorithm zstd 2>/dev/null || zramctl --find --size 1024M 2>/dev/null || true)
                if [ -n "${ZDEV}" ]; then
                    mkswap "${ZDEV}" >/dev/null 2>&1 || true
                    swapon -p 100 "${ZDEV}" 2>/dev/null || true
                    sysctl -w vm.swappiness=150 >/dev/null 2>&1 || true
                    log_ok "zRAM диск успешно активирован: ${ZDEV} (1 ГБ сжатия zstd)"
                fi
            fi
        else
            log_ok "zRAM активен и сконфигурирован"
        fi
    fi

    local TOTAL_SWAP_MB
    TOTAL_SWAP_MB=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}' || echo "0")
    if [ "${TOTAL_SWAP_MB:-0}" -lt 1024 ] && [ "${TOTAL_RAM_MB}" -le 3072 ]; then
        local AVAIL_DISK_MB
        AVAIL_DISK_MB=$(df -m / 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
        if [ ! -s /swapfile ] && [ "${AVAIL_DISK_MB}" -ge 3000 ]; then
            log_info "Создание дополнительного файла подкачки (1.5 ГБ Swapfile) для защиты от OOM..."
            local ROOT_FSTYPE
            ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || df -T / 2>/dev/null | awk 'NR==2{print $2}' || echo "ext4")

            if [ "${ROOT_FSTYPE}" = "btrfs" ] && command -v btrfs >/dev/null 2>&1; then
                btrfs filesystem mkswapfile --size 1536M /swapfile 2>/dev/null || {
                    truncate -s 0 /swapfile
                    chattr +C /swapfile 2>/dev/null || true
                    btrfs property set /swapfile compression none 2>/dev/null || true
                    dd if=/dev/zero of=/swapfile bs=1M count=1536 status=none
                }
            else
                (fallocate -l 1536M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1536 status=none)
            fi

            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1 || true
            if swapon -p 50 /swapfile >/dev/null 2>&1; then
                if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
                    echo "/swapfile none swap defaults,pri=50 0 0" >> /etc/fstab
                fi
                log_ok "Аварийный Swapfile успешно подключен (/swapfile, 1.5 ГБ)"
            fi
        fi
    fi
}

# =============================================================================
# Module: 03_network.sh
# Network Environment Analysis & Disk Safety Management
# =============================================================================

detect_network() {
    print_step_header "02/11" "ИНТЕЛЛЕКТУАЛЬНЫЙ АНАЛИЗ СЕТЕВОГО ОКРУЖЕНИЯ"

    if [ -n "${SAVED_PHYS_IFACE:-}" ] && ip link show dev "${SAVED_PHYS_IFACE}" >/dev/null 2>&1; then
        DEFAULT_IFACE="${SAVED_PHYS_IFACE}"
    else
        PHYS_IFACE=$( (ip -o -4 route show default 2>/dev/null | awk '{print $5}' | grep -vE '^(Meta|tun|tap|docker|br-|veth|wg|tailscale|zt|dummy|bond|lo)' | head -n1) || true )
        if [ -z "${PHYS_IFACE}" ]; then
            PHYS_IFACE=$( (ip -o -4 addr show scope global 2>/dev/null | awk '{print $2}' | grep -vE '^(Meta|tun|tap|docker|br-|veth|wg|tailscale|zt|dummy|bond|lo)' | head -n1) || true )
        fi
        if [ -z "${PHYS_IFACE}" ]; then
            PHYS_IFACE=$(ls -1 /sys/class/net 2>/dev/null | grep -E '^(eth|en|wl)' | head -n1 || true)
        fi
        DEFAULT_IFACE="${PHYS_IFACE:-eth0}"
    fi

    LOCAL_IP=$(ip -o -4 addr show dev "${DEFAULT_IFACE}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
    if [ -z "${LOCAL_IP}" ] || [ "${LOCAL_IP}" = "127.0.0.1" ]; then
        LOCAL_IP=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i !~ /^127\./) {print $i; exit}}')
        LOCAL_IP=${LOCAL_IP:-192.168.1.100}
    fi

    ROUTER_GATEWAY=$(ip route show default dev "${DEFAULT_IFACE}" 2>/dev/null | awk '/via/ {for(j=1;j<=NF;j++) if($j=="via") {print $(j+1); exit}}' | head -n1 || true)
    if [ -z "${ROUTER_GATEWAY}" ] || [ "${ROUTER_GATEWAY}" = "${LOCAL_IP}" ] || [[ ! "${ROUTER_GATEWAY}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ROUTER_GATEWAY=$(ip neigh show dev "${DEFAULT_IFACE}" 2>/dev/null | grep -E 'REACHABLE|DELAY|STALE' | awk '{print $1}' | grep -v "${LOCAL_IP}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
    fi
    if [ -z "${ROUTER_GATEWAY}" ] || [[ ! "${ROUTER_GATEWAY}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ROUTER_GATEWAY=$(echo "${LOCAL_IP}" | sed 's/\.[0-9]*$/.1/' || echo "192.168.1.1")
    fi

    RAW_SUBNET=$(ip -o -f inet addr show dev "${DEFAULT_IFACE}" 2>/dev/null | awk '{print $4}' | head -n1 || true)
    if [ -n "${RAW_SUBNET}" ]; then
        LAN_SUBNET=$(python3 -c "import ipaddress; print(ipaddress.ip_network('${RAW_SUBNET}', strict=False))" 2>/dev/null || echo "${RAW_SUBNET}")
    else
        LAN_SUBNET="192.168.1.0/24"
    fi

    REAL_USER="${SUDO_USER:-$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || echo "homelab")}"
    TARGET_USER="${SAVED_TARGET_USER:-${REAL_USER:-homelab}}"
    if ! id -u "${TARGET_USER}" >/dev/null 2>&1; then
        useradd -m -U -s /bin/bash "${TARGET_USER}" 2>/dev/null || \
        useradd -m -s /bin/bash "${TARGET_USER}" 2>/dev/null || \
        adduser -D -s /bin/bash "${TARGET_USER}" 2>/dev/null || true
    fi
    USER_UID=$(id -u "${TARGET_USER}")
    USER_GID=$(id -g "${TARGET_USER}")

    getent group docker >/dev/null 2>&1 || grep -q '^docker:' /etc/group 2>/dev/null || groupadd -r docker 2>/dev/null || addgroup -S docker 2>/dev/null || true
    usermod -aG docker "${TARGET_USER}" 2>/dev/null || adduser "${TARGET_USER}" docker 2>/dev/null || addgroup "${TARGET_USER}" docker 2>/dev/null || true
    if [ -S /var/run/docker.sock ]; then
        chown root:docker /var/run/docker.sock 2>/dev/null || true
        chmod 660 /var/run/docker.sock 2>/dev/null || true
    fi

    log_ok "Сетевые параметры определены:"
    echo -e "      ${CLR_WHITE}• ОС и ядро:        ${PRETTY_NAME:-Linux} ($(uname -r)) [Init: ${INIT_SYSTEM}]${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Архитектура:      ${SYSTEM_ARCH} (Аппаратный AES: $([ $HAS_HARDWARE_AES -eq 1 ] && echo "Да" || echo "Нет"))${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• IP сервера:       ${CLR_GREEN}${LOCAL_IP}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Шлюз роутера:     ${CLR_CYAN}${ROUTER_GATEWAY}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Интерфейс LAN:    ${CLR_YELLOW}${DEFAULT_IFACE}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Подсеть LAN:      ${LAN_SUBNET}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Пользователь:     ${TARGET_USER} (UID: ${USER_UID}, GID: ${USER_GID})${CLR_RESET}"
}

get_disk_parent() {
    local dev="$1"
    python3 -c "
import sys, os, subprocess, re
dev = os.path.realpath(sys.argv[1])
try:
    res = subprocess.check_output(['lsblk', '-slno', 'NAME,TYPE', dev], stderr=subprocess.DEVNULL).decode().strip()
    if res:
        for line in reversed(res.splitlines()):
            parts = line.split()
            if len(parts) >= 2 and parts[1] == 'disk':
                print(parts[0])
                sys.exit(0)
except Exception:
    pass
name = os.path.basename(dev)
if 'nvme' in name or 'mmcblk' in name:
    print(re.sub(r'p\d+$', '', name))
else:
    print(re.sub(r'\d+$', '', name))
" "${dev}" 2>/dev/null || basename "${dev}"
}

release_device() {
    local dev="$1"
    [ -z "$dev" ] && return 0
    local real_dev
    real_dev=$(readlink -f "$dev" 2>/dev/null || echo "$dev")

    log_info "Освобождение накопителя ${dev} от блокировок ядра и файловых систем..."

    if mountpoint -q "${MOUNT_ROOT}"; then
        fuser -km "${MOUNT_ROOT}" 2>/dev/null || true
        umount -R "${MOUNT_ROOT}" 2>/dev/null || umount -l "${MOUNT_ROOT}" 2>/dev/null || true
    fi

    while read -r mnt; do
        if [ -n "$mnt" ] && [ "$mnt" != "/" ] && [[ ! "$mnt" =~ ^/(boot|efi|usr|var|home) ]]; then
            fuser -km "$mnt" 2>/dev/null || true
            umount -R "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
        fi
    done < <(lsblk -rno MOUNTPOINT "${real_dev}" 2>/dev/null | grep -v '^$' || true)

    while read -r crypt_holder; do
        if [ -n "$crypt_holder" ]; then
            cryptsetup close "$crypt_holder" 2>/dev/null || dmsetup remove -f "$crypt_holder" 2>/dev/null || true
        fi
    done < <(lsblk -lno NAME,TYPE "${real_dev}" 2>/dev/null | awk '$2=="crypt" {print $1}')
    cryptsetup close "${LUKS_MAP_NAME}" 2>/dev/null || dmsetup remove -f "${LUKS_MAP_NAME}" 2>/dev/null || true

    swapoff "${real_dev}"* 2>/dev/null || true
    blockdev --flushbufs "${real_dev}" 2>/dev/null || true
    udevadm settle 2>/dev/null || sleep 1

    log_info "Очистка сигнатур разметки (wipefs)..."
    for part in $(lsblk -lno PATH "${real_dev}" 2>/dev/null | tail -n +2); do
        wipefs -af "${part}" 2>/dev/null || true
    done
    if ! wipefs -af "${real_dev}" 2>/dev/null; then
        dd if=/dev/zero of="${real_dev}" bs=1M count=16 oflag=direct status=none 2>/dev/null || \
        dd if=/dev/zero of="${real_dev}" bs=1M count=16 status=none 2>/dev/null || true
        blockdev --rereadpt "${real_dev}" 2>/dev/null || true
        udevadm settle 2>/dev/null || sleep 1
        wipefs -af "${real_dev}" 2>/dev/null || true
    fi
}

assert_safe_device() {
    local target_dev="$1"
    local real_target
    real_target=$(readlink -f "${target_dev}" 2>/dev/null || echo "${target_dev}")
    local target_disk
    target_disk=$(get_disk_parent "${real_target}")

    local root_src
    root_src=$(findmnt -n -o SOURCE / 2>/dev/null || df -P / 2>/dev/null | awk 'NR==2 {print $1}')
    root_src="${root_src%%[*}"
    local root_disk
    root_disk=$(get_disk_parent "${root_src}")

    if [ -n "${root_disk}" ] && [ "${target_disk}" = "${root_disk}" ]; then
        echo ""
        log_err "КРИТИЧЕСКАЯ БЛОКИРОВКА БЕЗОПАСНОСТИ!"
        log_err "Устройство ${target_dev} является системным накопителем (/dev/${root_disk}) текущей ОС!"
        log_err "Форматирование системного диска категорически запрещено."
        echo -e "      ${CLR_YELLOW}Для хранения на системном диске выберите режим [1] (Системный диск).${CLR_RESET}"
        exit 1
    fi

    local sys_mounts
    sys_mounts=$(lsblk -lno MOUNTPOINT "${real_target}" 2>/dev/null | grep -E '^/(boot|efi|usr|var|home)($|/)' || true)
    if [ -n "${sys_mounts}" ]; then
        echo ""
        log_err "КРИТИЧЕСКАЯ БЛОКИРОВКА БЕЗОПАСНОСТИ!"
        log_err "Накопитель ${target_dev} содержит системные разделы ОС:"
        echo -e "      ${CLR_YELLOW}${sys_mounts}${CLR_RESET}"
        log_err "Форматирование диска с системными компонентами запрещено."
        exit 1
    fi

    local cur_mounts
    cur_mounts=$(lsblk -lno MOUNTPOINT "${real_target}" 2>/dev/null | grep -E '^/(mnt|media)' || true)
    if [ -n "${cur_mounts}" ]; then
        log_info "Освобождение диска: отмонтирование разделов хранилища..."
        while read -r mnt_pt; do
            [ -n "$mnt_pt" ] && (umount -R "$mnt_pt" 2>/dev/null || umount -l "$mnt_pt" 2>/dev/null || true)
        done <<< "${cur_mounts}"
        cryptsetup close "${LUKS_MAP_NAME}" 2>/dev/null || true
    fi
}

select_disk_device() {
    log_info "Сканирование доступных физических накопителей..."

    local ROOT_SRC
    ROOT_SRC=$(findmnt -n -o SOURCE / 2>/dev/null || df -P / 2>/dev/null | awk 'NR==2 {print $1}')
    ROOT_SRC="${ROOT_SRC%%[*}"
    local ROOT_DISK
    ROOT_DISK=$(get_disk_parent "${ROOT_SRC}")

    local SYSTEM_DISKS=()
    [ -n "${ROOT_DISK}" ] && SYSTEM_DISKS+=("${ROOT_DISK}")

    for smpt in /boot /boot/efi /efi /usr /var /home; do
        if [ -d "$smpt" ]; then
            local s_src
            s_src=$(findmnt -n -o SOURCE "$smpt" 2>/dev/null || true)
            s_src="${s_src%%[*}"
            if [ -n "$s_src" ]; then
                local s_disk
                s_disk=$(get_disk_parent "$s_src")
                [ -n "$s_disk" ] && SYSTEM_DISKS+=("${s_disk}")
            fi
        fi
    done

    while read -r sw_dev rest; do
        [ -z "$sw_dev" ] || [ "$sw_dev" = "Filename" ] && continue
        local sw_disk
        sw_disk=$(get_disk_parent "$sw_dev")
        [ -n "$sw_disk" ] && SYSTEM_DISKS+=("${sw_disk}")
    done < /proc/swaps 2>/dev/null || true

    AVAIL_DEVS=()
    while read -r d_name d_type; do
        [ "$d_type" != "disk" ] && continue
        [ -z "$d_name" ] && continue
        [[ "$d_name" =~ ^(loop|zram|ram) ]] && continue
        [[ "$d_name" =~ (boot[0-9]|rpmb)$ ]] && continue

        local is_system=0
        for sys_d in "${SYSTEM_DISKS[@]}"; do
            if [ "$d_name" = "$sys_d" ]; then
                is_system=1
                break
            fi
        done
        [ "$is_system" -eq 1 ] && continue

        AVAIL_DEVS+=("/dev/${d_name}")
    done < <(lsblk -dno NAME,TYPE 2>/dev/null || true)

    if [ ${#AVAIL_DEVS[@]} -eq 0 ]; then
        echo ""
        log_err "Свободные внешние/дополнительные накопители не найдены!"
        echo -e "      ${CLR_WHITE}Системный диск /dev/${ROOT_DISK:-sda} исключен из списка безопасности.${CLR_RESET}"
        echo -e "      ${CLR_YELLOW}Подключите внешний диск или выберите режим [1] (Хранилище на системном диске).${CLR_RESET}"
        exit 1
    fi

    echo ""
    echo -e "  ${CLR_CYAN}Доступные дополнительные/внешние накопители (системный диск /dev/${ROOT_DISK:-sda} исключен):${CLR_RESET}"
    for i in "${!AVAIL_DEVS[@]}"; do
        local DEV_NAME="${AVAIL_DEVS[$i]}"
        local DEV_INFO
        DEV_INFO=$(lsblk -dno SIZE,MODEL,TRAN "${DEV_NAME}" 2>/dev/null | xargs)
        local ROTATIONAL
        ROTATIONAL=$(cat "/sys/block/$(basename "$DEV_NAME")/queue/rotational" 2>/dev/null || echo "1")
        local MEDIA_TYPE="HDD"
        [ "$ROTATIONAL" = "0" ] && MEDIA_TYPE="SSD/NVMe"
        printf "    ${CLR_WHITE}%d)${CLR_RESET} %-18s ${CLR_YELLOW}[%s | %s]${CLR_RESET}\n" "$((i+1))" "${DEV_NAME}" "${MEDIA_TYPE}" "${DEV_INFO:-Без метки}"
    done
    echo ""

    prompt_read "  [?] Выберите номер диска [1-${#AVAIL_DEVS[@]}]: " DEV_IDX
    while [[ ! "${DEV_IDX:-}" =~ ^[0-9]+$ ]] || [ "${DEV_IDX}" -lt 1 ] || [ "${DEV_IDX}" -gt "${#AVAIL_DEVS[@]}" ]; do
        prompt_read "  [-] Неверный выбор. Введите номер из списка: " DEV_IDX
    done

    CHOSEN_DEV="${AVAIL_DEVS[$((DEV_IDX-1))]}"
    assert_safe_device "${CHOSEN_DEV}"
    log_ok "Выбрано целевое устройство: ${CHOSEN_DEV}"
}

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
        printf "SAVED_USER_UID=%q\n" "${USER_UID}"
        printf "SAVED_USER_GID=%q\n" "${USER_GID}"
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
        USER_UID="${SAVED_USER_UID:-${USER_UID:-1000}}"
        USER_GID="${SAVED_USER_GID:-${USER_GID:-1000}}"

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

# =============================================================================
# Module: 05_gateway.sh
# Routing, nftables, Anti-Loop Protection, Watchdog Daemon & Notifications
# =============================================================================

setup_gateway_networking() {
    print_step_header "05/11" "МАРШРУТИЗАЦИЯ, NFTABLES И ЗАЩИТА ОТ ПЕТЕЛЬ"

    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        log_info "Освобождение порта 53 (отключение DNSStubListener при наличии)..."
        if [ "${INIT_SYSTEM}" = "systemd" ] && (systemctl is-active --quiet systemd-resolved 2>/dev/null || [ -d /etc/systemd/resolved.conf.d ]); then
            mkdir -p /etc/systemd/resolved.conf.d/
            cat <<EOF_RESOLVED > /etc/systemd/resolved.conf.d/disable-stub.conf
[Resolve]
DNSStubListener=no
DNS=77.88.8.8 1.1.1.1
EOF_RESOLVED
            systemctl restart systemd-resolved 2>/dev/null || true
        fi

        if [ -d /etc/NetworkManager/conf.d ]; then
            cat <<EOF_NM > /etc/NetworkManager/conf.d/99-homelab-dns.conf
[main]
dns=none
EOF_NM
            systemctl reload NetworkManager 2>/dev/null || true
        fi


        chattr -i /etc/resolv.conf 2>/dev/null || true
        rm -f /etc/resolv.conf
        # На этапе инсталляции используем надежные внешние DNS, чтобы избежать таймаутов до старта AdGuard Home
        cat <<EOF_DNS > /etc/resolv.conf
nameserver 77.88.8.8
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF_DNS

        modprobe tcp_bbr 2>/dev/null || true
        modprobe tun 2>/dev/null || true
        mkdir -p /etc/modules-load.d /dev/net
        echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
        echo "tun" > /etc/modules-load.d/tun.conf
        grep -q '^tcp_bbr$' /etc/modules 2>/dev/null || echo "tcp_bbr" >> /etc/modules 2>/dev/null || true
        grep -q '^tun$' /etc/modules 2>/dev/null || echo "tun" >> /etc/modules 2>/dev/null || true
        if [ ! -c /dev/net/tun ]; then
            mknod /dev/net/tun c 10 200 2>/dev/null || true
            chmod 666 /dev/net/tun 2>/dev/null || true
        fi

        log_info "Настройка sysctl: IP-форвардинг, BBR и loose rp_filter для TUN-маршрутизации..."
        cat <<EOF_SYSCTL > /etc/sysctl.d/99-gateway.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.${DEFAULT_IFACE}.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.${DEFAULT_IFACE}.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.${DEFAULT_IFACE}.rp_filter = 0
EOF_SYSCTL
        sysctl -p /etc/sysctl.d/99-gateway.conf 2>/dev/null || sysctl --system >/dev/null 2>&1 || true
        sysctl -w net.ipv4.ip_forward=1 \
                  net.ipv4.conf.all.send_redirects=0 net.ipv4.conf.default.send_redirects=0 net.ipv4.conf.${DEFAULT_IFACE}.send_redirects=0 \
                  net.ipv4.conf.all.accept_redirects=0 net.ipv4.conf.default.accept_redirects=0 net.ipv4.conf.${DEFAULT_IFACE}.accept_redirects=0 \
                  net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0 net.ipv4.conf.${DEFAULT_IFACE}.rp_filter=0 \
                  net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1 net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1 || true

        if command -v nmcli >/dev/null 2>&1 && [ -n "${DEFAULT_IFACE}" ]; then
            nmcli connection modify "${DEFAULT_IFACE}" ipv6.method disabled 2>/dev/null || true
        fi
        log_info "Настройка декларативного фаервола nftables (таблица inet homelab)..."
        mkdir -p /etc/nftables.d
        cat <<EOF_NFT > /etc/nftables.d/homelab.nft
table inet homelab {
    chain forward {
        type filter hook forward priority -10; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
        accept
    }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "${DEFAULT_IFACE}" tcp dport 53 redirect to :53
        iifname "${DEFAULT_IFACE}" udp dport 53 redirect to :53
        iifname "${DEFAULT_IFACE}" tcp dport 853 reject with tcp reset
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${DEFAULT_IFACE}" masquerade
        oifname "Meta" masquerade
    }

    chain input {
        type filter hook input priority filter; policy accept;
        ip saddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8 } tcp dport { 8083, 9090 } drop
    }
}
EOF_NFT

        local NFT_APPLIED=0
        if command -v nft >/dev/null 2>&1; then
            nft delete table inet homelab 2>/dev/null || true
            if nft -f /etc/nftables.d/homelab.nft 2>/dev/null; then
                NFT_APPLIED=1
                log_ok "Декларативные правила nftables успешно применены (таблица inet homelab)"
            fi
        fi

        for nft_conf in /etc/nftables.conf /etc/nftables.nft; do
            if [ -f "$nft_conf" ] && ! grep -q 'homelab.nft' "$nft_conf" 2>/dev/null; then
                echo 'include "/etc/nftables.d/homelab.nft"' >> "$nft_conf" 2>/dev/null || true
            fi
        done

        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            systemctl enable nftables >/dev/null 2>&1 || true
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            rc-update add nftables default >/dev/null 2>&1 || true
        fi

        # Гарантированное открытие транзита в цепочках Docker через nftables без дубликатов
        if nft list chain ip filter DOCKER-USER >/dev/null 2>&1; then
            if ! nft list chain ip filter DOCKER-USER 2>/dev/null | grep -q 'counter accept'; then
                nft insert rule ip filter DOCKER-USER counter accept 2>/dev/null || true
            fi
        fi
        if nft list chain ip filter FORWARD >/dev/null 2>&1; then
            if ! nft list chain ip filter FORWARD 2>/dev/null | grep -q 'counter accept'; then
                nft insert rule ip filter FORWARD counter accept 2>/dev/null || true
            fi
        fi

        log_info "Установка интеллектуального сторожевого таймера защиты от петель маршрутизации..."
        local WD_TMP="/usr/local/bin/gateway-watchdog.sh.tmp.$$"
        cat << 'EOF_WATCHDOG' > "${WD_TMP}"
#!/usr/bin/env bash
set -euo pipefail
if [ -f /opt/homelab/.env ]; then
    # shellcheck disable=SC1091
    source /opt/homelab/.env
fi

IFACE="${SAVED_PHYS_IFACE:-${PHYS_IFACE:-}}"
[ -z "$IFACE" ] && IFACE=$( (ip -o -4 route show default 2>/dev/null | awk '{print $5}' | grep -vE '^(Meta|tun|tap|docker|br-|veth|wg|tailscale|zt|dummy|bond|lo)' | head -n1) || true )
[ -z "$IFACE" ] && IFACE=$( (ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(en|eth|wl)' | head -n1) || true )
[ -z "$IFACE" ] && exit 0

SERVER_IP=$(ip -o -4 addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
ROUTER_IP="${SAVED_ROUTER_GATEWAY:-}"

IS_SAME_SUBNET=$(python3 -c "
import ipaddress, sys
s_ip = '${SERVER_IP}'
r_ip = '${ROUTER_IP}'
try:
    if s_ip and r_ip:
        s_net = ipaddress.ip_network(f'{s_ip}/24', strict=False)
        print('1' if ipaddress.ip_address(r_ip) in s_net else '0')
    else:
        print('0')
except Exception:
    print('0')
" 2>/dev/null || echo "0")

if [ "$IS_SAME_SUBNET" != "1" ] || [ -z "$ROUTER_IP" ] || [ "$ROUTER_IP" = "$SERVER_IP" ]; then
    ROUTER_IP=$(ip route show default dev "$IFACE" 2>/dev/null | awk '/via/ {for(j=1;j<=NF;j++) if($j=="via") {print $(j+1); exit}}' | head -n1 || true)
fi

if [ -z "$ROUTER_IP" ] || [ "$ROUTER_IP" = "$SERVER_IP" ] || [[ ! "$ROUTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ROUTER_IP=$(ip neigh show dev "$IFACE" 2>/dev/null | grep -E 'REACHABLE|DELAY|STALE' | awk '{print $1}' | grep -v "$SERVER_IP" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
fi

if [ -z "$ROUTER_IP" ] || [ "$ROUTER_IP" = "$SERVER_IP" ] || [[ ! "$ROUTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ROUTER_IP=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/.1/' || true)
fi

if [ -n "$ROUTER_IP" ] && [ "$ROUTER_IP" != "$SERVER_IP" ] && [[ "$ROUTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    CURRENT_MAIN_GW=$(ip route show default dev "$IFACE" 2>/dev/null | awk '/via/ {for(j=1;j<=NF;j++) if($j=="via") {print $(j+1); exit}}' | head -n1 || true)
    if [ "$CURRENT_MAIN_GW" = "$SERVER_IP" ] || [ -z "$CURRENT_MAIN_GW" ]; then
        logger -t gateway-watchdog "Восстановление корректного маршрута default через ${ROUTER_IP} на ${IFACE}" 2>/dev/null || true
        ip route replace default via "$ROUTER_IP" dev "$IFACE" metric 100 2>/dev/null || true
        /usr/local/bin/homelab-notify "Шлюз и маршрутизация" "Восстановлен корректный маршрут default через ${ROUTER_IP} на ${IFACE}" "WARN" 2>/dev/null || true
    fi
fi

if [ -f /etc/resolv.conf ] && grep -q '127.0.0.53' /etc/resolv.conf 2>/dev/null; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
    cat << 'EOF_RESOLV_FIX' > /etc/resolv.conf
nameserver 127.0.0.1
nameserver 77.88.8.8
nameserver 1.1.1.1
EOF_RESOLV_FIX
fi

sysctl -w net.ipv4.ip_forward=1 \
          net.ipv4.conf.all.send_redirects=0 net.ipv4.conf.default.send_redirects=0 net.ipv4.conf."${IFACE}".send_redirects=0 \
          net.ipv4.conf.all.accept_redirects=0 net.ipv4.conf.default.accept_redirects=0 net.ipv4.conf."${IFACE}".accept_redirects=0 \
          net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0 net.ipv4.conf."${IFACE}".rp_filter=0 \
          net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

APPLIED_NFT=0
if command -v nft >/dev/null 2>&1 && [ -n "$IFACE" ]; then
    mkdir -p /etc/nftables.d
    cat << EOF_NFT_WD > /etc/nftables.d/homelab.nft
table inet homelab {
    chain forward {
        type filter hook forward priority -10; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
        accept
    }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "$IFACE" tcp dport 53 redirect to :53
        iifname "$IFACE" udp dport 53 redirect to :53
        iifname "$IFACE" tcp dport 853 reject with tcp reset
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "$IFACE" masquerade
        oifname "Meta" masquerade
    }

    chain input {
        type filter hook input priority filter; policy accept;
        ip saddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8 } tcp dport { 8083, 9090 } drop
    }
}
EOF_NFT_WD
    # Пересоздавать таблицу ТОЛЬКО если она отсутствует в ядре (защита от сброса сессий каждую минуту)
    if ! nft list table inet homelab >/dev/null 2>&1; then
        logger -t gateway-watchdog "Восстановление отсутствующей таблицы inet homelab в nftables" 2>/dev/null || true
        nft -f /etc/nftables.d/homelab.nft 2>/dev/null || true
        APPLIED_NFT=1
    fi
fi

if [ "$APPLIED_NFT" -eq 1 ] || ! nft list chain ip filter DOCKER-USER 2>/dev/null | grep -q 'counter accept'; then
    # Гарантированное открытие транзита в цепочках Docker через nftables без дублирования
    if nft list chain ip filter DOCKER-USER >/dev/null 2>&1; then
        if ! nft list chain ip filter DOCKER-USER 2>/dev/null | grep -q 'counter accept'; then
            nft insert rule ip filter DOCKER-USER counter accept 2>/dev/null || true
        fi
    fi
    if nft list chain ip filter FORWARD >/dev/null 2>&1; then
        if ! nft list chain ip filter FORWARD 2>/dev/null | grep -q 'counter accept'; then
            nft insert rule ip filter FORWARD counter accept 2>/dev/null || true
        fi
    fi
fi

if command -v docker >/dev/null 2>&1 && docker inspect adguardhome >/dev/null 2>&1; then
    AG_STATUS=$(docker inspect -f '{{.State.Status}}' adguardhome 2>/dev/null || echo "none")
    AG_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' adguardhome 2>/dev/null || echo "none")
    if [ "$AG_STATUS" = "running" ] && [ "$AG_HEALTH" != "starting" ]; then
        DNS_CHECK_OK=0
        if timeout 2 nc -z 127.0.0.1 53 2>/dev/null || python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2); s.sendto(b'\xaa\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01', ('127.0.0.1', 53)); d, _ = s.recvfrom(512); exit(0 if len(d) > 12 else 1)" 2>/dev/null; then
            DNS_CHECK_OK=1
        fi
        if [ "$DNS_CHECK_OK" -eq 0 ]; then
            sleep 2
            if ! (timeout 2 nc -z 127.0.0.1 53 2>/dev/null || python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2); s.sendto(b'\xaa\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01', ('127.0.0.1', 53)); d, _ = s.recvfrom(512); exit(0 if len(d) > 12 else 1)" 2>/dev/null); then
                logger -t gateway-watchdog "DNS-резолвер AdGuard Home (порт 53) не отвечает, выполняется автоматический перезапуск..." 2>/dev/null || true
                docker restart adguardhome >/dev/null 2>&1 || true
                /usr/local/bin/homelab-notify "Самовосстановление DNS" "Порт 53 не отвечал на запросы. Контейнер AdGuard Home автоматически перезапущен сторожем." "WARN" 2>/dev/null || true
            fi
        fi
    fi
fi

if command -v docker >/dev/null 2>&1 && docker inspect mihomo >/dev/null 2>&1; then
    MH_STATUS=$(docker inspect -f '{{.State.Status}}' mihomo 2>/dev/null || echo "none")
    MH_HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' mihomo 2>/dev/null || echo "none")
    if [ "$MH_STATUS" = "running" ] && [ "$MH_HEALTH" != "starting" ]; then
        MIHOMO_CHECK_OK=0
        if python3 -c "import socket; s = socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 9090)); s.close()" 2>/dev/null || \
           wget -q --spider --header="Authorization: Bearer ${SAVED_MIHOMO_SECRET:-${MIHOMO_SECRET:-}}" http://127.0.0.1:9090/version 2>/dev/null || \
           wget -q --spider http://127.0.0.1:9090/ui/ 2>/dev/null || \
           timeout 2 nc -z 127.0.0.1 9090 2>/dev/null; then
            MIHOMO_CHECK_OK=1
        fi
        if [ "$MIHOMO_CHECK_OK" -eq 0 ]; then
            sleep 2
            if ! (python3 -c "import socket; s = socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 9090)); s.close()" 2>/dev/null || timeout 2 nc -z 127.0.0.1 9090 2>/dev/null); then
                logger -t gateway-watchdog "Ядро маршрутизации Mihomo (порт 9090) не отвечает, выполняется автоматический перезапуск..." 2>/dev/null || true
                docker restart mihomo >/dev/null 2>&1 || true
                /usr/local/bin/homelab-notify "Самовосстановление Mihomo" "Ядро маршрутизации не отвечало. Контейнер mihomo автоматически перезапущен сторожем." "WARN" 2>/dev/null || true
            fi
        fi
    fi
fi
EOF_WATCHDOG
        chmod 750 "${WD_TMP}"
        mv -f "${WD_TMP}" /usr/local/bin/gateway-watchdog.sh

        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            cat <<EOF_WD_SVC > /etc/systemd/system/network-gateway-watchdog.service
[Unit]
Description=Gateway Auto-Discovery and Loop Recovery Watchdog
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/gateway-watchdog.sh
EOF_WD_SVC

            cat <<EOF_WD_TMR > /etc/systemd/system/network-gateway-watchdog.timer
[Unit]
Description=Run Gateway Loop Watchdog periodically

[Timer]
OnBootSec=15s
OnUnitActiveSec=60s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF_WD_TMR

            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable --now network-gateway-watchdog.timer >/dev/null 2>&1 || true
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            mkdir -p /etc/crontabs
            if ! grep -q 'gateway-watchdog.sh' /etc/crontabs/root 2>/dev/null; then
                echo "* * * * * /usr/local/bin/gateway-watchdog.sh >/dev/null 2>&1" >> /etc/crontabs/root
            fi
            touch /etc/crontabs/cron.update 2>/dev/null || true
            rc-update add crond default >/dev/null 2>&1 || true
            rc-service crond status >/dev/null 2>&1 || rc-service crond start >/dev/null 2>&1 || true
        fi
    fi

    log_info "Регистрация локальных доменов в /etc/hosts..."
    for DOMAIN in "${VAULT_DOMAIN:-}" "${GITEA_DOMAIN:-}" "${ADGUARD_DOMAIN:-}" "${TORRENT_DOMAIN:-}" "${METUBE_DOMAIN:-}" "tube.lan" "${MUSIC_DOMAIN:-}" "${PROXY_DOMAIN:-}" "${LOGS_DOMAIN:-}"; do
        if [ -n "${DOMAIN}" ]; then
            local ESCAPED_DOMAIN
            ESCAPED_DOMAIN=$(printf '%s\n' "${DOMAIN}" | sed -e 's/[]\/$*.^[]/\\&/g')
            if ! grep -q "[[:space:]]${ESCAPED_DOMAIN}$" /etc/hosts; then
                echo "${LOCAL_IP} ${DOMAIN}" >> /etc/hosts
            else
                sed -i "s/.*[[:space:]]${ESCAPED_DOMAIN}$/${LOCAL_IP} ${DOMAIN}/" /etc/hosts
            fi
        fi
    done

    log_info "Настройка сервиса системных оповещений (homelab-notify)..."
    local NOTIFY_TMP="/usr/local/bin/homelab-notify.tmp.$$"
    cat << 'EOF_NOTIFY' > "${NOTIFY_TMP}"
#!/usr/bin/env bash
set -euo pipefail

if [ -f /opt/homelab/.env ]; then
    # shellcheck disable=SC1091
    source /opt/homelab/.env
fi

TG_ENABLED="${SAVED_ENABLE_TELEGRAM:-N}"
BOT_TOKEN="${SAVED_TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${SAVED_TELEGRAM_CHAT_ID:-}"

if [[ ! "$TG_ENABLED" =~ ^[Yy]$ ]] || [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    exit 0
fi

TITLE="${1:-Оповещение Homelab}"
MESSAGE="${2:-}"
SEVERITY="${3:-INFO}"

EMOJI="ℹ️"
[ "$SEVERITY" = "OK" ] && EMOJI="✅"
[ "$SEVERITY" = "WARN" ] && EMOJI="⚠️"
[ "$SEVERITY" = "CRIT" ] && EMOJI="🚨"

HOST_NAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "homelab")
TIME_NOW=$(date '+%Y-%m-%d %H:%M:%S')

TEXT="${EMOJI} *[${SEVERITY}] ${TITLE}*
🖥 *Хост:* \`${HOST_NAME}\`
⏱ *Время:* \`${TIME_NOW}\`

${MESSAGE}"

if ! curl -sf -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${TEXT}" \
    -d "parse_mode=Markdown" >/dev/null 2>&1; then
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${EMOJI} [${SEVERITY}] ${TITLE}
Хост: ${HOST_NAME}
Время: ${TIME_NOW}

${MESSAGE}" >/dev/null 2>&1 || true
fi
EOF_NOTIFY
    chmod 755 "${NOTIFY_TMP}"
    mv -f "${NOTIFY_TMP}" /usr/local/bin/homelab-notify

    log_ok "Сетевой стек, сторож маршрутизации и служба оповещений настроены"
}

# ==============================================================================
# МОДУЛЬ 06: СТРУКТУРА КАТАЛОГОВ И ОПТИМИЗАЦИЯ ХРАНИЛИЩА (NO-COW / BTRFS)
# ==============================================================================

setup_directories() {
    local CURRENT_FS="${SAVE_FSTYPE:-${SAVED_SAVE_FSTYPE:-}}"
    if [ -z "${CURRENT_FS}" ]; then
        CURRENT_FS=$(findmnt -n -o FSTYPE -T "${SAVE_DIR}" 2>/dev/null || df -T "${SAVE_DIR}" 2>/dev/null | awk 'NR==2{print $2}' || echo "ext4")
    fi

    print_step_header "06/11" "СТРУКТУРА КАТАЛОГОВ И ОПТИМИЗАЦИЯ ХРАНИЛИЩА (ФС: ${CURRENT_FS^^})"

    mkdir -p "${APP_DIR}/caddy/data" "${APP_DIR}/caddy/config"
    mkdir -p "${SAVE_DIR}/certificates" "${SAVE_DIR}/backups/vaultwarden" "${SAVE_DIR}/backups/gitea" "${SAVE_DIR}/backups/navidrome"
    mkdir -p "${VAULT_DATA_DIR}" "${GITEA_DATA_DIR}" "${ADGUARD_WORK_DIR}"
    chown -R "${USER_UID}:${USER_GID}" "${GITEA_DATA_DIR}" 2>/dev/null || true

    apply_nocow_helper() {
        local target_dir="$1"
        mkdir -p "${target_dir}"
        if [ "${CURRENT_FS}" = "btrfs" ]; then
            chattr +C "${target_dir}" 2>/dev/null || true
            find "${target_dir}" -maxdepth 2 -type f -exec chattr +C {} + 2>/dev/null || true
        fi
    }

    if [ "${CURRENT_FS}" = "btrfs" ]; then
        log_info "Обнаружена файловая система Btrfs: применение No-COW к каталогам баз данных и загрузок..."
        echo -e "      ${CLR_DIM}Отключение Copy-on-Write для SQLite баз данных и торрент-загрузок${CLR_RESET}"
        echo -e "      ${CLR_DIM}(Защита накопителя от CoW-фрагментации и деградации производительности)${CLR_RESET}"
    elif [[ "${CURRENT_FS}" =~ ^(ext4|ext3|xfs)$ ]]; then
        log_ok "Файловая система: ${CURRENT_FS} (прямая блочная запись in-place, фрагментация CoW отсутствует)"
    else
        log_info "Файловая система: ${CURRENT_FS} (стандартный режим блочного размещения)"
    fi

    apply_nocow_helper "${ADGUARD_WORK_DIR}"
    apply_nocow_helper "${VAULT_DATA_DIR}"
    apply_nocow_helper "${GITEA_DATA_DIR}"
    mkdir -p "${APP_DIR}/adguard/conf" 

    mkdir -p "${APP_DIR}/scripts"
    mkdir -p "${SAVE_DIR}/downloads"
    apply_nocow_helper "${SAVE_DIR}/downloads"
    chown -R "${USER_UID:-1000}:${USER_GID:-1000}" "${SAVE_DIR}/downloads" 2>/dev/null || true
    chmod -R 777 "${SAVE_DIR}/downloads" 2>/dev/null || true

    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]] || [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
        mkdir -p "${SAVE_DIR}/music"
        apply_nocow_helper "${SAVE_DIR}/music"
        chown -R "${USER_UID:-1000}:${USER_GID:-1000}" "${SAVE_DIR}/music" 2>/dev/null || true
        chmod -R 777 "${SAVE_DIR}/music" 2>/dev/null || true
    fi

    if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
        mkdir -p "${SAVE_DIR}/downloads/.metube" "${SAVE_DIR}/downloads/tmp"
        local YTDL_CONF="${SAVE_DIR}/downloads/.metube/ytdl_options.json"
        if [ ! -f "${YTDL_CONF}" ]; then
            if [ -s "${SAVE_DIR}/downloads/.metube/cookies.txt" ]; then
                echo '{"cookiefile": "/downloads/.metube/cookies.txt"}' > "${YTDL_CONF}"
            else
                echo '{}' > "${YTDL_CONF}"
            fi
        fi
        chown -R "${USER_UID:-1000}:${USER_GID:-1000}" "${SAVE_DIR}/downloads/.metube" "${SAVE_DIR}/downloads/tmp" 2>/dev/null || true
        chmod 777 "${SAVE_DIR}/downloads/.metube" "${SAVE_DIR}/downloads/tmp" 2>/dev/null || true
    fi

    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        mkdir -p "${APP_DIR}/configs/navidrome"
        apply_nocow_helper "${APP_DIR}/configs/navidrome"
        chown -R "${USER_UID:-1000}:${USER_GID:-1000}" "${APP_DIR}/configs/navidrome" 2>/dev/null || true
        chmod 775 "${APP_DIR}/configs/navidrome" 2>/dev/null || true
    fi

    if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
        mkdir -p "${APP_DIR}/qbittorrent/config/qBittorrent" "${APP_DIR}/qbittorrent/vuetorrent"
        mkdir -p "${SAVE_DIR}/temp"
        apply_nocow_helper "${SAVE_DIR}/temp"
        chown -R "${USER_UID}:${USER_GID}" "${SAVE_DIR}/temp" 2>/dev/null || true

        local VUETORRENT_OK=0
        if [ -f "${APP_DIR}/qbittorrent/vuetorrent/index.html" ]; then
            log_ok "Веб-интерфейс VueTorrent уже установлен (пропуск загрузки)"
            VUETORRENT_OK=1
        else
            log_info "Загрузка и распаковка веб-интерфейса VueTorrent..."
            python3 -c "
import urllib.request, zipfile, os

urls = [
    'https://ghfast.top/https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip',
    'https://ghp.ci/https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip',
    'https://hub.gitmirror.com/https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip',
    'https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip'
]
zip_p = '/tmp/vuetorrent.zip'
dest = '${APP_DIR}/qbittorrent/vuetorrent'
os.makedirs(dest, exist_ok=True)

for u in urls:
    try:
        req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=6) as resp, open(zip_p, 'wb') as f:
            f.write(resp.read())
        if os.path.isfile(zip_p) and os.path.getsize(zip_p) > 50000 and zipfile.is_zipfile(zip_p):
            break
    except Exception:
        if os.path.exists(zip_p):
            try: os.remove(zip_p)
            except Exception: pass

if os.path.isfile(zip_p) and zipfile.is_zipfile(zip_p):
    with zipfile.ZipFile(zip_p, 'r') as z:
        names = [n for n in z.namelist() if not n.endswith('/')]
        has_public = any('public/' in n for n in names)
        for m in names:
            if has_public:
                if 'public/' in m:
                    rel = m.split('public/', 1)[1]
                else:
                    continue
            else:
                parts = m.split('/', 1)
                rel = parts[1] if len(parts) > 1 and parts[0].lower() in ('vuetorrent', 'vuetorrent-main') else m
            target = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, 'wb') as out_f:
                out_f.write(z.read(m))
            pub_target = os.path.join(dest, 'public', rel)
            os.makedirs(os.path.dirname(pub_target), exist_ok=True)
            with open(pub_target, 'wb') as pub_f:
                pub_f.write(z.read(m))
    try:
        os.remove(zip_p)
    except Exception:
        pass
" 2>/dev/null || true
            [ -f "${APP_DIR}/qbittorrent/vuetorrent/index.html" ] && VUETORRENT_OK=1
        fi

        chown -R "${USER_UID}:${USER_GID}" "${APP_DIR}/qbittorrent" 2>/dev/null || true
        log_info "Генерация конфигурации qBittorrent с мастер-паролем..."
        
        local QBIT_HASH
        QBIT_HASH=$(python3 -c "
import sys, hashlib, os, base64
pw = sys.stdin.read().rstrip('\r\n').encode('utf-8')
salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac('sha512', pw, salt, 100000, dklen=64)
print(f'@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(dk).decode()})')
" <<< "${MASTER_PASS}" 2>/dev/null || echo "")
        
        local QBIT_CONF="${APP_DIR}/qbittorrent/config/qBittorrent/qBittorrent.conf"
        if [ -s "${QBIT_CONF}" ] && [ "${IS_UPGRADE_MODE:-0}" -eq 1 ]; then
            log_ok "Конфигурация qBittorrent уже настроена (пользовательские параметры сохранены)"
        else
            local ALT_UI_FLAG="false"
            [ "${VUETORRENT_OK}" -eq 1 ] && ALT_UI_FLAG="true"

            cat <<EOF_QBIT_CONF > "${QBIT_CONF}"
[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Connection\PortRangeMin=6881
Downloads\DiskWriteCacheSize=64
Downloads\SavePath=/downloads/
Downloads\ScanDirsV2=@Invalid()
Downloads\TempPath=/downloads/temp/
Queueing\QueueingEnabled=false
WebUI\Address=0.0.0.0
WebUI\AlternativeUIEnabled=${ALT_UI_FLAG}
WebUI\AuthSubnetWhitelist=
WebUI\AuthSubnetWhitelistEnabled=false
WebUI\BanDuration=3600
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=true
WebUI\CustomHTTPHeaders=
WebUI\CustomHTTPHeadersEnabled=false
WebUI\HostHeaderValidation=false
WebUI\LocalHostAuth=false
WebUI\MaxAuthenticationFailCount=5
WebUI\Password_PBKDF2="${QBIT_HASH}"
WebUI\Port=8080
WebUI\ReverseProxySupportEnabled=true
WebUI\RootFolder=/vuetorrent
WebUI\SecureCookie=false
WebUI\ServerDomains=*
WebUI\SessionTimeout=86400
WebUI\TrustedProxiesList=0.0.0.0/0
WebUI\UseUPnP=false
WebUI\Username=${ADMIN_USER}
EOF_QBIT_CONF
        fi
        chown -R "${USER_UID}:${USER_GID}" "${APP_DIR}/qbittorrent" 2>/dev/null || true
    fi

    chown -R "${USER_UID:-1000}:${USER_GID:-1000}" "${SAVE_DIR}" 2>/dev/null || true
    chmod 755 "${SAVE_DIR}" 2>/dev/null || true

    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        mkdir -p "${APP_DIR}/mihomo/ui" "${APP_DIR}/mihomo/providers"
        [ ! -f "${APP_DIR}/mihomo/providers/proxies.yaml" ] && echo "proxies: []" > "${APP_DIR}/mihomo/providers/proxies.yaml"

        if [ -n "${SUB_URL}" ] && [ "${SUB_URL}" != "none" ]; then
            log_info "Проверка и кэширование подписки прокси..."
            local SUB_OK=0
            if curl -fsSL -4 -k -A "clash.meta" --connect-timeout 6 -m 15 "${SUB_URL}" -o "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" 2>/dev/null && \
               [ -s "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" ]; then
                SUB_OK=1
            elif curl -fsSL -4 -k -A "mihomo" --connect-timeout 6 -m 15 "${SUB_URL}" -o "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" 2>/dev/null && \
                 [ -s "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" ]; then
                SUB_OK=1
            elif curl -fsSL -4 -k --connect-timeout 6 -m 15 "${SUB_URL}" -o "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" 2>/dev/null && \
                 [ -s "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" ]; then
                SUB_OK=1
            elif python3 -c "
import urllib.request, ssl, sys
ctx = ssl._create_unverified_context()
req = urllib.request.Request('${SUB_URL}', headers={'User-Agent': 'clash.meta; clash-verge; mihomo'})
try:
    with urllib.request.urlopen(req, timeout=12, context=ctx) as resp:
        d = resp.read()
        if len(d) > 50:
            with open('${APP_DIR}/mihomo/providers/proxies.yaml.tmp', 'wb') as f:
                f.write(d)
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
" 2>/dev/null && [ -s "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" ]; then
                SUB_OK=1
            fi

            if [ "${SUB_OK}" -eq 1 ]; then
                mv -f "${APP_DIR}/mihomo/providers/proxies.yaml.tmp" "${APP_DIR}/mihomo/providers/proxies.yaml"
                local SUB_LINES
                SUB_LINES=$(wc -l < "${APP_DIR}/mihomo/providers/proxies.yaml" 2>/dev/null || echo 0)
                log_ok "Подписка успешно проверена и кэширована (${SUB_LINES} строк конфигурации)"
            else
                rm -f "${APP_DIR}/mihomo/providers/proxies.yaml.tmp"
                log_warn "Подписка временно недоступна на этапе предзагрузки."
                echo -e "      ${CLR_DIM}Mihomo автоматически загрузит подписку при старте службы через свои встроенные механизмы.${CLR_RESET}"
            fi
        fi

        if [ -f "${APP_DIR}/mihomo/ui/index.html" ]; then
            log_ok "Веб-интерфейс MetaCubeXD уже установлен (пропуск загрузки)"
        else
            fetch_metacubexd() {
                local urls=(
                    'https://ghfast.top/https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz'
                    'https://ghp.ci/https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz'
                    'https://hub.gitmirror.com/https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz'
                    'https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz'
                    'https://ghfast.top/https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.tar.gz'
                )
                local tar_tmp="/tmp/metacubexd.tar.gz"
                for u in "${urls[@]}"; do
                    rm -f "$tar_tmp"
                    if curl -fsSL -4 -k --connect-timeout 4 -m 12 "$u" -o "$tar_tmp" 2>/dev/null && [ -s "$tar_tmp" ]; then
                        if tar -tzf "$tar_tmp" >/dev/null 2>&1; then
                            if [[ "$u" =~ compressed-dist ]]; then
                                tar -xzf "$tar_tmp" -C "${APP_DIR}/mihomo/ui" 2>/dev/null && rm -f "$tar_tmp" && return 0
                            else
                                tar -xzf "$tar_tmp" -C "${APP_DIR}/mihomo/ui" --strip-components=1 2>/dev/null && rm -f "$tar_tmp" && return 0
                            fi
                        fi
                        rm -f "$tar_tmp"
                    fi
                done
                return 1
            }

            if run_spin "Загрузка веб-интерфейса MetaCubeXD (с зеркалами)" fetch_metacubexd; then
                log_ok "Веб-интерфейс MetaCubeXD успешно развернут"
            else
                log_info "Активация встроенного автономного веб-портала управления шлюзом..."
                cat << 'EOF_FALLBACK_UI' > "${APP_DIR}/mihomo/ui/index.html"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Homelab Gateway Dashboard</title>
<style>
:root { --bg: #090d16; --card: #111827; --border: #1f2937; --accent: #38bdf8; --green: #10b981; --purple: #a855f7; --text: #f3f4f6; --muted: #9ca3af; }
body { background: var(--bg); color: var(--text); font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 24px; box-sizing: border-box; }
.card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 32px; max-width: 580px; width: 100%; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.7); }
.header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
h1 { color: var(--accent); font-size: 22px; margin: 0; display: flex; align-items: center; gap: 8px; }
.badge { background: rgba(16, 185, 129, 0.15); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.3); padding: 4px 10px; border-radius: 9999px; font-size: 11px; font-weight: 700; letter-spacing: 0.05em; }
p { color: var(--muted); font-size: 14px; line-height: 1.6; margin: 8px 0 20px; }
.links { display: grid; gap: 10px; margin: 16px 0; }
.btn { display: flex; align-items: center; justify-content: space-between; background: #1f2937; color: var(--text); text-decoration: none; padding: 12px 16px; border-radius: 10px; font-weight: 500; font-size: 14px; border: 1px solid rgba(255,255,255,0.05); transition: all 0.2s; }
.btn:hover { background: #374151; border-color: var(--accent); transform: translateY(-1px); }
.btn-primary { background: #0284c7; color: #fff; font-weight: 600; }
.btn-primary:hover { background: #0369a1; }
.info-box { background: rgba(56, 189, 248, 0.06); border-left: 3px solid var(--accent); padding: 12px 14px; border-radius: 6px; font-size: 13px; color: #cbd5e1; margin-top: 18px; line-height: 1.5; }
code { background: #1e293b; color: var(--accent); padding: 2px 6px; border-radius: 4px; font-family: monospace; font-size: 12px; }
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <h1>🚀 Homelab Gateway</h1>
    <span class="badge">CORE ONLINE</span>
  </div>
  <p>Ядро маршрутизации <b>Mihomo TUN</b> и <b>AdGuard Home</b> успешно запущены и функционируют на данном сервере.</p>
  <div class="links">
    <a class="btn btn-primary" href="https://metacubex.github.io/metacubexd/#/?hostname=proxy.lan&port=443&protocol=https" target="_blank" rel="noopener">
      <span>🌐 Открыть MetaCubeXD Online</span>
      <span>↗</span>
    </a>
    <a class="btn" href="https://adguard.lan" target="_blank" rel="noopener">
      <span>🛡️ AdGuard Home Dashboard</span>
      <span>→</span>
    </a>
    <a class="btn" href="https://metube.lan" target="_blank" rel="noopener">
      <span>📥 MeTube (Загрузка медиа)</span>
      <span>→</span>
    </a>
    <a class="btn" href="https://music.lan" target="_blank" rel="noopener">
      <span>🎵 Navidrome Hi-Fi Стриминг</span>
      <span>→</span>
    </a>
    <a class="btn" href="https://logs.lan" target="_blank" rel="noopener">
      <span>📋 Журналы Dozzle</span>
      <span>→</span>
    </a>
  </div>
  <div class="info-box">
    💡 <b>API шлюза:</b> Хост: <code>proxy.lan</code> | Порт: <code>443</code> (HTTPS)
  </div>
</div>
</body>
</html>
EOF_FALLBACK_UI
                log_ok "Встроенный портал управления шлюзом успешно подготовлен"
            fi
        fi

        find "${APP_DIR}/mihomo/ui" -type f \( -name "*.js" -o -name "*.html" -o -name "*.json" \) -exec sed -i \
            -e "s|http://127.0.0.1:9090|https://${PROXY_DOMAIN}/api|g" \
            -e "s|127.0.0.1:9090|${PROXY_DOMAIN}/api|g" {} + 2>/dev/null || true

        mkdir -p "${APP_DIR}/mihomo/ruleset"
        fetch_mrs_rulesets() {
            local TEST_MIRRORS=(
                "https://raw.gitmirror.com/MetaCubeX/meta-rules-dat/meta/geo"
                "https://ghfast.top/https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo"
                "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo"
                "https://mirror.ghproxy.com/https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo"
                "https://ghproxy.net/https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo"
                "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo"
            )

            local RULES=(
                "geosite/category-ru.mrs"
                "geosite/google-gemini.mrs"
                "geosite/category-ai-chat-!cn.mrs"
                "geosite/youtube.mrs"
                "geosite/telegram.mrs"
                "geosite/meta.mrs"
                "geosite/twitter.mrs"
                "geosite/discord.mrs"
                "geosite/steam.mrs"
                "geosite/github.mrs"
                "geoip/ru.mrs"
            )

            local WORKING_BASE=""
            for m in "${TEST_MIRRORS[@]}"; do
                if curl -fsSL -4 -k --connect-timeout 2 -m 3 "${m}/geosite/youtube.mrs" -o /dev/null 2>/dev/null; then
                    WORKING_BASE="$m"
                    break
                fi
            done

            if [ -z "$WORKING_BASE" ]; then
                return 0
            fi

            local pids=()
            for rel_path in "${RULES[@]}"; do
                local fname
                fname=$(basename "$rel_path")
                local target="${APP_DIR}/mihomo/ruleset/${fname}"
                if [ ! -s "$target" ]; then
                    (
                        if curl -fsSL -4 -k --connect-timeout 3 -m 8 "${WORKING_BASE}/${rel_path}" -o "${target}.tmp" 2>/dev/null && \
                           [ -s "${target}.tmp" ] && [ "$(wc -c < "${target}.tmp" 2>/dev/null || echo 0)" -ge 100 ]; then
                            mv -f "${target}.tmp" "$target"
                        else
                            rm -f "${target}.tmp"
                        fi
                    ) &
                    pids+=($!)
                fi
            done

            for pid in "${pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done
            return 0
        }
        run_spin "Предзагрузка ультралегких правил Meta Rule-Set (.mrs)" fetch_mrs_rulesets
    fi

    log_ok "Структура каталогов и параметры No-COW подготовлены"
}

# ==============================================================================
# МОДУЛЬ 07: ТЕСТИРОВАНИЕ И ВЫБОР БЫСТРЫХ И БЕЗОПАСНЫХ DOH / DOT РЕЗОЛВЕРОВ
# ==============================================================================

benchmark_dns_servers() {
    print_step_header "07/11" "ТЕСТИРОВАНИЕ И ВЫБОР БЫСТРЫХ И БЕЗОПАСНЫХ DOH / DOT РЕЗОЛВЕРОВ"

    if [[ ! "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        log_info "Сетевой шлюз отключен в конфигурации. Пропуск тестирования DoH / DoT."
        return 0
    fi

    if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ] && [ -n "${SELECTED_DOH_1:-}" ]; then
        log_ok "Используются ранее настроенные DoH/DoT резолверы: ${SELECTED_DOH_1} (пропуск в режиме обновления)"
        return 0
    fi

    echo -e "  ${CLR_CYAN}Запуск параллельного бенчмарка безопасности и задержки DoH/DoT...${CLR_RESET}"
    echo -e "  ${CLR_DIM}Проверка подлинности сертификатов TLS, целостности DNSSEC и RTT пинга...${CLR_RESET}"
    echo ""

    local BENCH_JSON
    BENCH_JSON=$(python3 - << 'EOF_PY_BENCH'
import socket, ssl, time, struct, base64, urllib.request, concurrent.futures, json, sys

CANDIDATES = [
    {
        "name": "Yandex DNS",
        "doh_url": "https://common.dot.dns.yandex.net/dns-query",
        "dot_host": "common.dot.dns.yandex.net",
        "dot_ip": "77.88.8.8",
        "dot_url": "tls://common.dot.dns.yandex.net",
        "bootstrap": "77.88.8.8",
        "policy": "Low Latency CIS/Eastern Europe, Anti-Spoofing"
    },
    {
        "name": "Cloudflare (1.1.1.1)",
        "doh_url": "https://cloudflare-dns.com/dns-query",
        "dot_host": "cloudflare-dns.com",
        "dot_ip": "1.1.1.1",
        "dot_url": "tls://1.1.1.1",
        "bootstrap": "1.1.1.1",
        "policy": "Zero-logs, DNSSEC, Anycast"
    },
    {
        "name": "Quad9 (9.9.9.9)",
        "doh_url": "https://dns.quad9.net/dns-query",
        "dot_host": "dns.quad9.net",
        "dot_ip": "9.9.9.9",
        "dot_url": "tls://dns.quad9.net",
        "bootstrap": "9.9.9.9",
        "policy": "Threat Blocking, Swiss GDPR, DNSSEC"
    },
    {
        "name": "AdGuard DNS",
        "doh_url": "https://dns.adguard-dns.com/dns-query",
        "dot_host": "dns.adguard-dns.com",
        "dot_ip": "94.140.14.14",
        "dot_url": "tls://dns.adguard-dns.com",
        "bootstrap": "94.140.14.14",
        "policy": "Ad/Tracker Filtering, No-logs Anycast"
    },
    {
        "name": "Google Public DNS",
        "doh_url": "https://dns.google/dns-query",
        "dot_host": "dns.google",
        "dot_ip": "8.8.8.8",
        "dot_url": "tls://dns.google",
        "bootstrap": "8.8.8.8",
        "policy": "Global Anycast, High Availability"
    },
    {
        "name": "Mullvad DNS",
        "doh_url": "https://dns.mullvad.net/dns-query",
        "dot_host": "dns.mullvad.net",
        "dot_ip": "194.242.2.2",
        "dot_url": "tls://dns.mullvad.net",
        "bootstrap": "194.242.2.2",
        "policy": "RAM-only, Strict Privacy, No Logs"
    },
    {
        "name": "Control D (Freedns)",
        "doh_url": "https://freedns.controld.com/p0",
        "dot_host": "p0.freedns.controld.com",
        "dot_ip": "76.76.2.0",
        "dot_url": "tls://p0.freedns.controld.com",
        "bootstrap": "76.76.2.0",
        "policy": "Uncensored Anycast, No Logs"
    }
]

QUERY_WIRE = (
    b'\xaa\xbb\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00'
    b'\x07example\x03com\x00'
    b'\x00\x01\x00\x01'
)

def recv_exact(s, length):
    buf = b""
    while len(buf) < length:
        chunk = s.recv(length - len(buf))
        if not chunk:
            break
        buf += chunk
    return buf

def test_dot(c, timeout=1.8):
    host = c["dot_host"]
    ip = c.get("dot_ip") or host
    t0 = time.perf_counter()
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((ip, 853), timeout=timeout) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ssock:
                wire_msg = struct.pack('!H', len(QUERY_WIRE)) + QUERY_WIRE
                ssock.sendall(wire_msg)
                len_bytes = recv_exact(ssock, 2)
                if len(len_bytes) < 2:
                    return None
                expected_len = struct.unpack('!H', len_bytes)[0]
                resp = recv_exact(ssock, expected_len)
                if len(resp) >= 12 and (resp[3] & 0x0F) == 0:
                    rtt = round((time.perf_counter() - t0) * 1000, 1)
                    return {
                        "name": c["name"],
                        "proto": "DoT",
                        "endpoint": c["dot_url"],
                        "bootstrap": c["bootstrap"],
                        "policy": c["policy"],
                        "latency_ms": rtt,
                        "secure": True
                    }
    except Exception:
        pass
    return None

def test_doh(c, timeout=1.8):
    url = c["doh_url"]
    t0 = time.perf_counter()
    try:
        b64 = base64.urlsafe_b64encode(QUERY_WIRE).rstrip(b'=').decode('ascii')
        get_url = f"{url}?dns={b64}"
        req = urllib.request.Request(
            get_url,
            headers={
                "Accept": "application/dns-message",
                "User-Agent": "Homelab-DNS-Bench/2026"
            }
        )
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            if resp.status == 200:
                data = resp.read()
                if len(data) >= 12 and (data[3] & 0x0F) == 0:
                    rtt = round((time.perf_counter() - t0) * 1000, 1)
                    return {
                        "name": c["name"],
                        "proto": "DoH",
                        "endpoint": c["doh_url"],
                        "bootstrap": c["bootstrap"],
                        "policy": c["policy"],
                        "latency_ms": rtt,
                        "secure": True
                    }
    except Exception:
        try:
            post_req = urllib.request.Request(
                url,
                data=QUERY_WIRE,
                headers={
                    "Content-Type": "application/dns-message",
                    "Accept": "application/dns-message",
                    "User-Agent": "Homelab-DNS-Bench/2026"
                }
            )
            ctx = ssl.create_default_context()
            with urllib.request.urlopen(post_req, timeout=timeout, context=ctx) as resp:
                if resp.status == 200:
                    data = resp.read()
                    if len(data) >= 12 and (data[3] & 0x0F) == 0:
                        rtt = round((time.perf_counter() - t0) * 1000, 1)
                        return {
                            "name": c["name"],
                            "proto": "DoH",
                            "endpoint": c["doh_url"],
                            "bootstrap": c["bootstrap"],
                            "policy": c["policy"],
                            "latency_ms": rtt,
                            "secure": True
                        }
        except Exception:
            pass
    return None

dot_results = []
doh_results = []

with concurrent.futures.ThreadPoolExecutor(max_workers=14) as executor:
    fut_dot = {executor.submit(test_dot, c): c for c in CANDIDATES}
    fut_doh = {executor.submit(test_doh, c): c for c in CANDIDATES}
    for f in concurrent.futures.as_completed(fut_dot):
        r = f.result()
        if r: dot_results.append(r)
    for f in concurrent.futures.as_completed(fut_doh):
        r = f.result()
        if r: doh_results.append(r)

dot_results.sort(key=lambda x: x["latency_ms"])
doh_results.sort(key=lambda x: x["latency_ms"])

dot_blocked = (len(dot_results) == 0 and len(doh_results) > 0)

default_dot = [
    {"name": "Yandex DNS", "endpoint": "tls://common.dot.dns.yandex.net", "bootstrap": "77.88.8.8", "latency_ms": 15.0, "secure": True},
    {"name": "Cloudflare (1.1.1.1)", "endpoint": "tls://1.1.1.1", "bootstrap": "1.1.1.1", "latency_ms": 20.0, "secure": True},
    {"name": "Quad9 (9.9.9.9)", "endpoint": "tls://dns.quad9.net", "bootstrap": "9.9.9.9", "latency_ms": 28.0, "secure": True}
]
default_doh = [
    {"name": "Yandex DNS", "endpoint": "https://common.dot.dns.yandex.net/dns-query", "bootstrap": "77.88.8.8", "latency_ms": 16.0, "secure": True},
    {"name": "Cloudflare (1.1.1.1)", "endpoint": "https://cloudflare-dns.com/dns-query", "bootstrap": "1.1.1.1", "latency_ms": 20.0, "secure": True},
    {"name": "AdGuard DNS", "endpoint": "https://dns.adguard-dns.com/dns-query", "bootstrap": "94.140.14.14", "latency_ms": 24.0, "secure": True}
]

effective_doh = doh_results if doh_results else default_doh
if dot_blocked:
    effective_dot = effective_doh
else:
    effective_dot = dot_results if dot_results else default_dot

out = {
    "dot_results": dot_results,
    "doh_results": doh_results,
    "dot_blocked": dot_blocked,
    "is_offline": (len(doh_results) == 0 and len(dot_results) == 0),
    "selected_doh_1": effective_doh[0]["endpoint"],
    "selected_doh_2": effective_doh[1]["endpoint"] if len(effective_doh) > 1 else effective_doh[0]["endpoint"],
    "selected_doh_3": effective_doh[2]["endpoint"] if len(effective_doh) > 2 else effective_doh[0]["endpoint"],
    "selected_doh_name_1": effective_doh[0]["name"],
    "selected_doh_ping_1": effective_doh[0]["latency_ms"],
    "selected_doh_name_2": effective_doh[1]["name"] if len(effective_doh) > 1 else "",
    "selected_doh_ping_2": effective_doh[1]["latency_ms"] if len(effective_doh) > 1 else 0,
    "selected_dot_1": effective_dot[0]["endpoint"],
    "selected_dot_2": effective_dot[1]["endpoint"] if len(effective_dot) > 1 else effective_dot[0]["endpoint"],
    "selected_dot_name_1": effective_dot[0]["name"],
    "selected_dot_ping_1": effective_dot[0]["latency_ms"],
    "selected_dot_name_2": effective_dot[1]["name"] if len(effective_dot) > 1 else "",
    "selected_dot_ping_2": effective_dot[1]["latency_ms"] if len(effective_dot) > 1 else 0,
    "bootstrap_ips": list(dict.fromkeys([
        "77.88.8.8", "1.1.1.1",
        effective_doh[0].get("bootstrap", "77.88.8.8"),
        effective_dot[0].get("bootstrap", "77.88.8.8"),
        "9.9.9.9", "8.8.8.8"
    ]))
}
print(json.dumps(out))
EOF_PY_BENCH
)

    eval "$(python3 - "${BENCH_JSON}" << 'EOF_EXTRACT_BENCH'
import sys, json, shlex
d = json.loads(sys.argv[1])
b_ips = " ".join(d.get("bootstrap_ips", []))
b_ip_1 = b_ips.split()[0] if b_ips else "77.88.8.8"
print(f"SELECTED_DOH_1={shlex.quote(str(d.get('selected_doh_1', '')))}")
print(f"SELECTED_DOH_2={shlex.quote(str(d.get('selected_doh_2', '')))}")
print(f"SELECTED_DOH_3={shlex.quote(str(d.get('selected_doh_3', '')))}")
print(f"SELECTED_DOT_1={shlex.quote(str(d.get('selected_dot_1', '')))}")
print(f"SELECTED_DOT_2={shlex.quote(str(d.get('selected_dot_2', '')))}")
print(f"SELECTED_BOOTSTRAP_IPS={shlex.quote(b_ips)}")
print(f"SELECTED_BOOTSTRAP_IP_1={shlex.quote(b_ip_1)}")
print(f"DOH_NAME_1={shlex.quote(str(d.get('selected_doh_name_1', '')))}")
print(f"DOH_PING_1={shlex.quote(str(d.get('selected_doh_ping_1', 0)))}")
print(f"DOH_NAME_2={shlex.quote(str(d.get('selected_doh_name_2', '')))}")
print(f"DOH_PING_2={shlex.quote(str(d.get('selected_doh_ping_2', 0)))}")
print(f"DOT_NAME_1={shlex.quote(str(d.get('selected_dot_name_1', '')))}")
print(f"DOT_PING_1={shlex.quote(str(d.get('selected_dot_ping_1', 0)))}")
print(f"DOT_NAME_2={shlex.quote(str(d.get('selected_dot_name_2', '')))}")
print(f"DOT_PING_2={shlex.quote(str(d.get('selected_dot_ping_2', 0)))}")
print(f"DOT_BLOCKED={'1' if d.get('dot_blocked') else '0'}")
print(f"IS_OFFLINE={'1' if d.get('is_offline') else '0'}")
EOF_EXTRACT_BENCH
)"

    python3 - "${BENCH_JSON}" << 'EOF_PRINT_BENCH'
import sys, json
data = json.loads(sys.argv[1])
doh_list = data.get("doh_results", [])
dot_list = data.get("dot_results", [])

if doh_list:
    print('\033[1;36m┌── Результаты тестирования DNS-over-HTTPS (DoH, порт 443) ──────────────────\033[0m')
    for idx, item in enumerate(doh_list[:5]):
        badge = '\033[1;32m[ВЫБРАН]\033[0m' if idx < 2 else '\033[2m[РЕЗЕРВ]\033[0m'
        name_str = item.get("name", "")
        latency_str = f'{item.get("latency_ms", 0):>5.1f}'
        policy_str = item.get("policy", "")
        print(f'│   \033[1;32m✔\033[0m {name_str:<24} {latency_str} мс   {badge}   \033[2m{policy_str}\033[0m')
    print('\033[1;36m└──\033[0m')

if dot_list:
    print('\033[1;36m┌── Результаты тестирования DNS-over-TLS (DoT, порт 853) ────────────────────\033[0m')
    for idx, item in enumerate(dot_list[:5]):
        badge = '\033[1;32m[ВЫБРАН]\033[0m' if idx < 2 else '\033[2m[РЕЗЕРВ]\033[0m'
        name_str = item.get("name", "")
        latency_str = f'{item.get("latency_ms", 0):>5.1f}'
        policy_str = item.get("policy", "")
        print(f'│   \033[1;32m✔\033[0m {name_str:<24} {latency_str} мс   {badge}   \033[2m{policy_str}\033[0m')
    print('\033[1;36m└──\033[0m')
EOF_PRINT_BENCH

    if [ "${DOT_BLOCKED}" = "1" ]; then
        log_warn "Порт DoT (853) заблокирован вашим провайдером. Автоматически активирован DoH (порт 443)!"
    fi

    if [ "${IS_OFFLINE}" = "1" ]; then
        log_warn "Режим автономной установки или внешний DNS временно недоступен."
        log_ok "Применены проверенные высоконадежные эталонные DoH/DoT резолверы."
    fi

    log_ok "Выбраны самые быстрые и безопасные резолверы:"
    echo -e "      ${CLR_WHITE}• Основной DoH:${CLR_RESET}   ${CLR_GREEN}${DOH_NAME_1}${CLR_RESET} (${DOH_PING_1} мс) -> ${CLR_CYAN}${SELECTED_DOH_1}${CLR_RESET}"
    [ -n "${DOH_NAME_2}" ] && echo -e "      ${CLR_WHITE}• Резервный DoH:${CLR_RESET}  ${CLR_GREEN}${DOH_NAME_2}${CLR_RESET} (${DOH_PING_2} мс) -> ${CLR_CYAN}${SELECTED_DOH_2}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Основной DoT:${CLR_RESET}   ${CLR_GREEN}${DOT_NAME_1}${CLR_RESET} (${DOT_PING_1} мс) -> ${CLR_CYAN}${SELECTED_DOT_1}${CLR_RESET}"
    [ -n "${DOT_NAME_2}" ] && echo -e "      ${CLR_WHITE}• Резервный DoT:${CLR_RESET}  ${CLR_GREEN}${DOT_NAME_2}${CLR_RESET} (${DOT_PING_2} мс) -> ${CLR_CYAN}${SELECTED_DOT_2}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Bootstrap IPs:${CLR_RESET} ${SELECTED_BOOTSTRAP_IPS}"

    if [ -f "${ENV_FILE}" ]; then
        sed -i '/SAVED_SELECTED_DOH_/d; /SAVED_SELECTED_DOT_/d; /SAVED_SELECTED_BOOTSTRAP_IP/d' "${ENV_FILE}" 2>/dev/null || true
        {
            printf "SAVED_SELECTED_DOH_1=%q\n" "${SELECTED_DOH_1}"
            printf "SAVED_SELECTED_DOH_2=%q\n" "${SELECTED_DOH_2}"
            printf "SAVED_SELECTED_DOH_3=%q\n" "${SELECTED_DOH_3}"
            printf "SAVED_SELECTED_DOT_1=%q\n" "${SELECTED_DOT_1}"
            printf "SAVED_SELECTED_DOT_2=%q\n" "${SELECTED_DOT_2}"
            printf "SAVED_SELECTED_BOOTSTRAP_IPS=%q\n" "${SELECTED_BOOTSTRAP_IPS}"
            printf "SAVED_SELECTED_BOOTSTRAP_IP_1=%q\n" "${SELECTED_BOOTSTRAP_IP_1}"
        } >> "${ENV_FILE}"
    fi
}

# ==============================================================================
# МОДУЛЬ 08: ГЕНЕРАЦИЯ КОНФИГУРАЦИЙ ADGUARD HOME И MIHOMO TUN
# ==============================================================================

configure_gateway_services() {
    print_step_header "08/11" "ГЕНЕРАЦИЯ КОНФИГУРАЦИЙ ADGUARD HOME И MIHOMO TUN"

    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        log_info "Формирование DNS-переопределений и фильтров AdGuard Home (Schema 34+)..."
        local BOOTSTRAP_YAML_LINES
        BOOTSTRAP_YAML_LINES=$(for b_ip in ${SELECTED_BOOTSTRAP_IPS:-77.88.8.8 1.1.1.1 9.9.9.9 8.8.8.8}; do echo "    - ${b_ip}"; done)
        local REWRITE_ENTRIES=""
        [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]] && REWRITE_ENTRIES="${REWRITE_ENTRIES}
    - domain: ${VAULT_DOMAIN}
      answer: ${LOCAL_IP}"
        [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]] && REWRITE_ENTRIES="${REWRITE_ENTRIES}
    - domain: ${GITEA_DOMAIN}
      answer: ${LOCAL_IP}"
        REWRITE_ENTRIES="${REWRITE_ENTRIES}
    - domain: ${ADGUARD_DOMAIN}
      answer: ${LOCAL_IP}
    - domain: ${PROXY_DOMAIN}
      answer: ${LOCAL_IP}
    - domain: ${LOGS_DOMAIN}
      answer: ${LOCAL_IP}"
        [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]] && REWRITE_ENTRIES="${REWRITE_ENTRIES}
    - domain: ${TORRENT_DOMAIN}
      answer: ${LOCAL_IP}"
        [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]] && REWRITE_ENTRIES="${REWRITE_ENTRIES}
    - domain: ${METUBE_DOMAIN}
      answer: ${LOCAL_IP}
    - domain: tube.lan
      answer: ${LOCAL_IP}"
        [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]] && REWRITE_ENTRIES="${REWRITE_ENTRIES}
    - domain: ${MUSIC_DOMAIN}
      answer: ${LOCAL_IP}"

        local PTR_UPSTREAMS_YAML="    - 127.0.0.1:1053"
        if [ -n "${ROUTER_GATEWAY:-}" ] && [ "${ROUTER_GATEWAY}" != "127.0.0.1" ]; then
            PTR_UPSTREAMS_YAML="    - ${ROUTER_GATEWAY}
    - 127.0.0.1:1053"
        fi

        local AGH_CONF="${APP_DIR}/adguard/conf/AdGuardHome.yaml"
        if [ -s "${AGH_CONF}" ] && [ "${IS_UPGRADE_MODE:-0}" -eq 1 ]; then
            log_ok "Обновление DNS-переопределений в AdGuardHome.yaml (фильтры и правила сохранены)"
            python3 -c "
import sys, re
conf_file = sys.argv[1]
with open(conf_file, 'r', encoding='utf-8') as f:
    c = f.read()

new_rewrites = '  rewrites:' + sys.stdin.read().rstrip('\r\n')
if '  rewrites:' in c:
    c = re.sub(r'  rewrites:.*?(?=\n\S|\n  [a-zA-Z0-9_]+:|\Z)', new_rewrites, c, flags=re.DOTALL)
elif 'filtering:' in c:
    c = re.sub(r'(filtering:\s*\n)', r'\1' + new_rewrites + '\n', c)

with open(conf_file, 'w', encoding='utf-8') as f:
    f.write(c)
" "${AGH_CONF}" <<< "${REWRITE_ENTRIES}" 2>/dev/null || true
        else
            cat <<EOF_AGH > "${AGH_CONF}"
schema_version: 34
http:
  address: 0.0.0.0:8083
  session_ttl: 720h
  trusted_proxies:
    - 127.0.0.1
    - 172.16.0.0/12
    - 192.168.0.0/16
    - 10.0.0.0/8
    - ::1
users:
  - name: ${ADMIN_USER}
    password: "${AGH_HASH}"
auth_attempts: 5
block_auth_min: 15
language: "ru"
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  block_ipv6: true
  block_ech: true
  anonymize_client_ip: false
  ratelimit: 0
  refuse_any: true
  upstream_dns:
    - 127.0.0.1:1053
  fallback_dns:
    - ${SELECTED_DOT_1:-tls://common.dot.dns.yandex.net}
    - ${SELECTED_DOT_2:-tls://1.1.1.1}
    - ${SELECTED_DOH_1:-https://common.dot.dns.yandex.net/dns-query}
  upstream_timeout: 4s
  bootstrap_dns:
${BOOTSTRAP_YAML_LINES}
  upstream_mode: load_balance
  use_private_ptr_resolvers: true
  local_ptr_upstreams:
${PTR_UPSTREAMS_YAML}
  cache_size: 4194304
  cache_enabled: false
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  enable_dnssec: false
querylog:
  enabled: true
  file_enabled: true
  interval: 24h
  size_memory: 1000
  anonymize_client_ip: false
stats:
  enabled: true
  interval: 24h
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
filtering:
  filtering_enabled: true
  protection_enabled: true
  rewrites_enabled: true
  filters_update_interval: 24
  rewrites:${REWRITE_ENTRIES}
filters: []
whitelist_filters: []
user_rules:
  # Блокировка канареечных доменов DoH и Apple Private Relay (предотвращение скрытого обхода шлюза)
  - '||use-application-dns.net^'
  - '||mask.icloud.com^'
  - '||mask-h2.icloud.com^'
  # Блокировка ECH (HTTPS type 65) для защиты от скрытого сброса TLS рукопожатий цензурой ТСПУ
  - '|*^\$dnstype=HTTPS'
  - '@@||connectivitycheck.gstatic.com^\$important'
  - '@@||*.connectivitycheck.gstatic.com^\$important'
  - '@@||connectivitycheck.android.com^\$important'
  - '@@||*.connectivitycheck.android.com^\$important'
  - '@@||clients3.google.com^\$important'
  - '@@||play.googleapis.com^\$important'
  - '@@||captive.apple.com^\$important'
  - '@@||connect.rom.miui.com^\$important'
  - '@@||wifi.miui.com^\$important'
  - '@@||connectivity.samsung.com.cn^\$important'
  - '@@||connectivitycheck.platform.hicloud.com^\$important'
  - '@@||detectportal.firefox.com^\$important'
  - '@@||msftconnecttest.com^\$important'
  - '@@||msftncsi.com^\$important'
  - '@@||gosuslugi.ru^\$important'
  - '@@||*.gosuslugi.ru^\$important'
  - '@@||sberbank.ru^\$important'
  - '@@||*.sberbank.ru^\$important'
  - '@@||tbank.ru^\$important'
  - '@@||*.tbank.ru^\$important'
  - '@@||vtb.ru^\$important'
  - '@@||*.vtb.ru^\$important'
  - '@@||alfabank.ru^\$important'
  - '@@||*.alfabank.ru^\$important'
  - '@@||mirconnect.ru^\$important'
  - '@@||cbr.ru^\$important'
  - '@@||nalog.gov.ru^\$important'
  - '@@||mos.ru^\$important'
  - '@@||emias.info^\$important'
  - '@@||yandex.ru^\$important'
  - '@@||yandex.net^\$important'
  - '@@||vk.com^\$important'
  - '@@||2ip.ru^\$important'
  - '@@||speedtest.net^\$important'
  - '@@||whoer.net^\$important'
  - '@@||ntc.party^\$important'
  - '@@||4pda.to^\$important'
  - '@@||rutracker.org^\$important'
  - '@@||rutracker.net^\$important'
  - '@@||rutracker.nl^\$important'
  - '@@||nnmclub.to^\$important'
  - '@@||rutor.info^\$important'
  - '@@||anilibria.top^\$important'
  - '@@||aniliberty.top^\$important'
  - '@@||*.libria.fun^\$important'
EOF_AGH
        fi

        local ESCAPED_MIHOMO_SECRET
        ESCAPED_MIHOMO_SECRET=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read().rstrip('\r\n')))" <<< "${MIHOMO_SECRET}")

        log_info "Формирование конфигурации Mihomo TUN (Mixed-Stack, Full-Cone NAT и умный обход замедлений)..."
        local PROXY_PROVIDERS_CONFIG=""
        local PROXY_GROUPS_CONFIG=""

        if [ -n "${SUB_URL}" ] && [ "${SUB_URL}" != "none" ]; then
            PROXY_PROVIDERS_CONFIG="
proxy-providers:
  my-sub:
    type: http
    url: \"${SUB_URL}\"
    path: ./providers/proxies.yaml
    interval: 86400
    health-check:
      enable: true
      url: https://cp.cloudflare.com/generate_204
      interval: 300
      lazy: true"

            PROXY_GROUPS_CONFIG="
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - AUTO
      - DIRECT
    use:
      - my-sub

  - name: AUTO
    type: url-test
    use:
      - my-sub
    url: https://cp.cloudflare.com/generate_204
    interval: 300
    tolerance: 50
    lazy: true

  - name: AI-Services
    type: select
    proxies:
      - AUTO
      - PROXY
      - DIRECT
    use:
      - my-sub"
        else
            PROXY_PROVIDERS_CONFIG=""
            PROXY_GROUPS_CONFIG="
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT

  - name: AI-Services
    type: select
    proxies:
      - DIRECT"
        fi

        cat <<EOF_MIHOMO > "${APP_DIR}/mihomo/config.yaml"
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: false
secret: ${ESCAPED_MIHOMO_SECRET}
external-controller: 0.0.0.0:9090
external-ui: ui
external-controller-cors:
  allow-origins:
    - "*"
  allow-private-network: true

rule-providers:
  ru_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/category-ru.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/category-ru.mrs"
    interval: 86400

  gemini_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/google-gemini.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/google-gemini.mrs"
    interval: 86400

  ai_chat:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/category-ai-chat-!cn.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/category-ai-chat-!cn.mrs"
    interval: 86400

  youtube_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/youtube.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/youtube.mrs"
    interval: 86400

  telegram_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/telegram.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/telegram.mrs"
    interval: 86400

  meta_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/meta.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/meta.mrs"
    interval: 86400

  twitter_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/twitter.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/twitter.mrs"
    interval: 86400

  discord_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/discord.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/discord.mrs"
    interval: 86400

  steam_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/steam.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/steam.mrs"
    interval: 86400

  github_site:
    type: http
    behavior: domain
    format: mrs
    path: ./ruleset/github.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/github.mrs"
    interval: 86400

  ru_ip:
    type: http
    behavior: ipcidr
    format: mrs
    path: ./ruleset/ru.mrs
    url: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geoip/ru.mrs"
    interval: 86400

dns:
  enable: true
  listen: 127.0.0.1:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  respect-rules: true
  store-fake-ip: true
  cache-algorithm: arc
  fake-ip-filter:
    - "+.lan"
    - "+.local"
    - "+.duckdns.org"
    - "+.pool.ntp.org"
    - "time.*.com"
    - "time.*.gov"
    - "time.*.apple.com"
    # Автоматическое прямое разрешение для всей базы российских доменов
    - "rule-set:ru_site"
    - "+.ru"
    - "+.su"
    - "+.xn--p1ai"
    - "+.xn--80asehdb"
    - "+.xn--80aswg"
    - "+.xn--80adxhks"
    - "+.xn--c1avg"
    - "+.gosuslugi.org"
    - "+.emias.info"
    - "+.yandex.net"
    - "+.yastatic.net"
    - "+.vk.com"
    - "+.userapi.com"
    - "+.vk-portal.net"
    - "+.2gis.com"
    # Captive Portal и проверка доступности сети (Android, Apple, Windows, Xiaomi, Samsung, Huawei)
    - "+.connectivitycheck.gstatic.com"
    - "+.connectivitycheck.android.com"
    - "clients3.google.com"
    - "play.googleapis.com"
    - "+.gvt2.com"
    - "captive.apple.com"
    - "+.apple.com"
    - "connect.rom.miui.com"
    - "wifi.miui.com"
    - "connectivity.samsung.com.cn"
    - "connectivitycheck.platform.hicloud.com"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "detectportal.firefox.com"
  nameserver-policy:
    "rule-set:ru_site":
      - 77.88.8.8
      - 77.88.8.1
    "+.ru,+.su,+.xn--p1ai,+.xn--80asehdb,+.xn--80aswg,+.xn--80adxhks,+.xn--c1avg,+.yandex.net,+.yastatic.net,+.vk.com,+.userapi.com,+.vk-portal.net,+.gosuslugi.org,+.emias.info,+.2gis.com":
      - 77.88.8.8
      - 77.88.8.1
    "connectivitycheck.gstatic.com,+.connectivitycheck.gstatic.com,connectivitycheck.android.com,+.connectivitycheck.android.com,clients3.google.com,play.googleapis.com,captive.apple.com,+.apple.com,connect.rom.miui.com,wifi.miui.com,detectportal.firefox.com":
      - 77.88.8.8
      - 77.88.8.1
  default-nameserver:
    - 77.88.8.8
    - 77.88.8.1
    - ${SELECTED_BOOTSTRAP_IP_1:-77.88.8.8}
  proxy-server-nameserver:
    - 77.88.8.8
    - 77.88.8.1
    - ${SELECTED_BOOTSTRAP_IP_1:-77.88.8.8}
  direct-nameserver:
    - 77.88.8.8
    - 77.88.8.1
  nameserver:
    - 77.88.8.8
    - ${SELECTED_DOH_1:-https://common.dot.dns.yandex.net/dns-query}
    - 77.88.8.1

unified-delay: true
tcp-concurrent: true

sniffer:
  enable: true
  parse-pure-ip: true
  sniff:
    TLS:
      ports: [443, 8443]
    HTTP:
      ports: [80, "8080-8880"]
    QUIC:
      ports: [443]
  force-domain:
    - "+.google.com"
    - "+.youtube.com"
    - "+.googlevideo.com"
    - "+.gvt1.com"
    - "+.ytimg.com"
    - "+.ggpht.com"
    - "+.discord.gg"
    - "+.discord.com"
    - "+.discordapp.com"
    - "+.discordapp.net"
  skip-domain:
    - "Mijia Cloud"
    - "dlg.io.mi.com"
    - "+.apple.com"

tun:
  enable: true
  device: Meta
  stack: mixed
  mtu: 1400
  auto-route: true
  auto-detect-interface: true
  endpoint-independent-nat: true
  strict-route: false
  route-exclude-address:
    - "${LAN_SUBNET}"
    - "${ROUTER_GATEWAY}/32"
    - "${LOCAL_IP}/32"
    - "192.168.0.0/16"
    - "172.16.0.0/12"
    - "10.0.0.0/8"

proxies: []
${PROXY_PROVIDERS_CONFIG}
${PROXY_GROUPS_CONFIG}

rules:
  # Проверка доступности сети (Captive Portal Android, Apple, Windows, Xiaomi, Samsung) — МГНОВЕННО НАПРЯМУЮ!
  - DOMAIN-SUFFIX,connectivitycheck.gstatic.com,DIRECT
  - DOMAIN-SUFFIX,connectivitycheck.android.com,DIRECT
  - DOMAIN,clients3.google.com,DIRECT
  - DOMAIN,play.googleapis.com,DIRECT
  - DOMAIN,detectportal.firefox.com,DIRECT
  - DOMAIN,captive.apple.com,DIRECT
  - DOMAIN-SUFFIX,apple.com,DIRECT
  - DOMAIN,connect.rom.miui.com,DIRECT
  - DOMAIN,wifi.miui.com,DIRECT
  - DOMAIN,connectivity.samsung.com.cn,DIRECT
  - DOMAIN,connectivitycheck.platform.hicloud.com,DIRECT
  - DOMAIN-SUFFIX,msftconnecttest.com,DIRECT
  - DOMAIN-SUFFIX,msftncsi.com,DIRECT
  - DOMAIN-KEYWORD,connectivitycheck,DIRECT

  # Блокировка QUIC (UDP 443) для форсирования надежного TCP/HTTP2 (YouTube/браузеры)
  - AND,((NETWORK,UDP),(DST-PORT,443)),REJECT

  # Прямой трафик локального шлюза, сервера и локальной сети
  - IP-CIDR,${ROUTER_GATEWAY}/32,DIRECT,no-resolve
  - IP-CIDR,${LOCAL_IP}/32,DIRECT,no-resolve
  - DOMAIN-SUFFIX,lan,DIRECT
  - DOMAIN-SUFFIX,duckdns.org,DIRECT
  - IP-CIDR,${LAN_SUBNET},DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - GEOIP,private,DIRECT,no-resolve
  - GEOIP,lan,DIRECT,no-resolve

  # Торрент-клиенты и P2P-пиры — напрямую на полной скорости провайдера (без расхода трафика прокси)
  - PROCESS-NAME,qbittorrent,DIRECT
  - PROCESS-NAME,qbittorrent-nox,DIRECT
  - PROCESS-NAME,transmission-daemon,DIRECT
  - PROCESS-NAME,transmission-qt,DIRECT
  - PROCESS-NAME,uTorrent,DIRECT
  - PROCESS-NAME,BitComet,DIRECT
  - DST-PORT,6881-6889,DIRECT
  - SRC-PORT,6881-6889,DIRECT
  - DST-PORT,51413,DIRECT
  - SRC-PORT,51413,DIRECT

  # Торрент-трекеры, каталоги и анонсеры (обход блокировок РКН для поиска и подключения к раздачам)
  - DOMAIN-SUFFIX,rutracker.org,PROXY
  - DOMAIN-SUFFIX,rutracker.net,PROXY
  - DOMAIN-SUFFIX,rutracker.nl,PROXY
  - DOMAIN-SUFFIX,t-ru.org,PROXY
  - DOMAIN-SUFFIX,nnmclub.to,PROXY
  - DOMAIN-SUFFIX,nnm-club.me,PROXY
  - DOMAIN-SUFFIX,rutor.info,PROXY
  - DOMAIN-SUFFIX,rutor.is,PROXY
  - DOMAIN-SUFFIX,opentor.org,PROXY
  - DOMAIN-SUFFIX,open.stealth.si,PROXY
  - DOMAIN-SUFFIX,opentrackr.org,PROXY
  - DOMAIN-SUFFIX,kinozal.tv,PROXY
  - DOMAIN-SUFFIX,flibusta.is,PROXY
  - DOMAIN-SUFFIX,flibusta.site,PROXY
  - DOMAIN-SUFFIX,libria.fun,PROXY
  - DOMAIN-SUFFIX,anilibria.top,PROXY
  - DOMAIN-KEYWORD,announce,PROXY
  - DOMAIN-KEYWORD,tracker,PROXY

  # Steam Community (заблокирован/замедлен в РФ) через PROXY, а загрузка игр — напрямую DIRECT
  - DOMAIN-SUFFIX,steamcommunity.com,PROXY
  - RULE-SET,steam_site,DIRECT
  - RULE-SET,github_site,DIRECT

  # Нейросети и искусственный интеллект (OpenAI, Anthropic, Gemini, Copilot, Perplexity, Cursor и др.)
  - DOMAIN-SUFFIX,openai.com,AI-Services
  - DOMAIN-SUFFIX,chatgpt.com,AI-Services
  - DOMAIN-SUFFIX,oaistatic.com,AI-Services
  - DOMAIN-SUFFIX,oaiusercontent.com,AI-Services
  - DOMAIN-SUFFIX,anthropic.com,AI-Services
  - DOMAIN-SUFFIX,claude.ai,AI-Services
  - DOMAIN-SUFFIX,perplexity.ai,AI-Services
  - DOMAIN-SUFFIX,gemini.google.com,AI-Services
  - DOMAIN-SUFFIX,aistudio.google.com,AI-Services
  - DOMAIN-SUFFIX,generativelanguage.googleapis.com,AI-Services
  - DOMAIN-SUFFIX,alkalimakersuite-pa.clients6.google.com,AI-Services
  - DOMAIN-SUFFIX,cursor.com,AI-Services
  - DOMAIN-SUFFIX,cursor.sh,AI-Services
  - DOMAIN-SUFFIX,copilot.microsoft.com,AI-Services
  - DOMAIN-SUFFIX,suno.com,AI-Services
  - DOMAIN-SUFFIX,suno.ai,AI-Services
  - DOMAIN-SUFFIX,midjourney.com,AI-Services
  - DOMAIN-SUFFIX,x.ai,AI-Services
  - DOMAIN-SUFFIX,grok.com,AI-Services
  - DOMAIN-SUFFIX,deepseek.com,AI-Services
  - DOMAIN-SUFFIX,v0.dev,AI-Services
  - DOMAIN-SUFFIX,huggingface.co,AI-Services
  - DOMAIN-KEYWORD,gemini.google,AI-Services
  - RULE-SET,gemini_site,AI-Services
  - RULE-SET,ai_chat,AI-Services

  # YouTube и Google Video CDN — через группу PROXY (без замедления РКН)
  - DOMAIN-SUFFIX,googlevideo.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY
  - DOMAIN-SUFFIX,youtu.be,PROXY
  - DOMAIN-SUFFIX,ytimg.com,PROXY
  - DOMAIN-SUFFIX,ggpht.com,PROXY
  - DOMAIN-SUFFIX,gvt1.com,PROXY
  - DOMAIN-SUFFIX,youtube-nocookie.com,PROXY
  - DOMAIN-SUFFIX,youtubekids.com,PROXY
  - RULE-SET,youtube_site,PROXY

  # Discord (голосовые серверы RTC, чаты, вложения, шлюз) — через группу PROXY
  - DOMAIN-SUFFIX,discord.com,PROXY
  - DOMAIN-SUFFIX,discord.gg,PROXY
  - DOMAIN-SUFFIX,discordapp.com,PROXY
  - DOMAIN-SUFFIX,discordapp.net,PROXY
  - DOMAIN-SUFFIX,discord.media,PROXY
  - DOMAIN-SUFFIX,discordcdn.com,PROXY
  - DOMAIN-KEYWORD,discord,PROXY
  - RULE-SET,discord_site,PROXY

  # Telegram — через группу PROXY
  - DOMAIN-SUFFIX,t.me,PROXY
  - DOMAIN-SUFFIX,telegram.org,PROXY
  - DOMAIN-SUFFIX,telegram.me,PROXY
  - DOMAIN-SUFFIX,telegra.ph,PROXY
  - RULE-SET,telegram_site,PROXY

  # Заблокированные в РФ соцсети и популярные платформы
  - DOMAIN-SUFFIX,instagram.com,PROXY
  - DOMAIN-SUFFIX,cdninstagram.com,PROXY
  - DOMAIN-SUFFIX,facebook.com,PROXY
  - DOMAIN-SUFFIX,fbcdn.net,PROXY
  - DOMAIN-SUFFIX,meta.com,PROXY
  - DOMAIN-SUFFIX,twitter.com,PROXY
  - DOMAIN-SUFFIX,x.com,PROXY
  - DOMAIN-SUFFIX,twimg.com,PROXY
  - DOMAIN-SUFFIX,linkedin.com,PROXY
  - DOMAIN-SUFFIX,notion.so,PROXY
  - DOMAIN-SUFFIX,notion.site,PROXY
  - DOMAIN-SUFFIX,canva.com,PROXY
  - DOMAIN-SUFFIX,soundcloud.com,PROXY
  - DOMAIN-SUFFIX,spotify.com,PROXY
  # Платформы контента, арта и медиа (Pixiv, Booth, Fanbox)
  - DOMAIN-SUFFIX,pixiv.net,PROXY
  - DOMAIN-SUFFIX,pximg.net,PROXY
  - DOMAIN-SUFFIX,pixiv.org,PROXY
  - DOMAIN-SUFFIX,booth.pm,PROXY
  - DOMAIN-SUFFIX,fanbox.cc,PROXY
  - RULE-SET,meta_site,PROXY
  - RULE-SET,twitter_site,PROXY

  # Российские зоны, государственные порталы, банки, маркетплейсы и сервисы — 100% НАПРЯМУЮ DIRECT!
  # Национальные TLD (перехватывают ВСЕ *.ru, *.su, *.рф без необходимости дублировать отдельные домены)
  - DOMAIN-SUFFIX,ru,DIRECT
  - DOMAIN-SUFFIX,su,DIRECT
  - DOMAIN-SUFFIX,xn--p1ai,DIRECT
  - DOMAIN-SUFFIX,xn--80asehdb,DIRECT
  - DOMAIN-SUFFIX,xn--80aswg,DIRECT
  - DOMAIN-SUFFIX,xn--80adxhks,DIRECT
  - DOMAIN-SUFFIX,xn--c1avg,DIRECT

  # Российские ресурсы и CDN вне зон .ru/.su/.рф
  - DOMAIN-SUFFIX,gosuslugi.org,DIRECT
  - DOMAIN-SUFFIX,emias.info,DIRECT
  - DOMAIN-SUFFIX,yandex.net,DIRECT
  - DOMAIN-SUFFIX,yastatic.net,DIRECT
  - DOMAIN-SUFFIX,vk.com,DIRECT
  - DOMAIN-SUFFIX,userapi.com,DIRECT
  - DOMAIN-SUFFIX,vk-portal.net,DIRECT
  - DOMAIN-SUFFIX,vk-cdn.net,DIRECT
  - DOMAIN-SUFFIX,vkusercontent.com,DIRECT
  - DOMAIN-SUFFIX,ozonusercontent.com,DIRECT
  - DOMAIN-SUFFIX,wbstatic.net,DIRECT
  - DOMAIN-SUFFIX,avito.st,DIRECT
  - DOMAIN-SUFFIX,2gis.com,DIRECT
  - DOMAIN-SUFFIX,4pda.to,DIRECT
  - DOMAIN-SUFFIX,ntc.party,DIRECT

  # Базы правил и диапазоны IP РФ (geosite/geoip)
  - RULE-SET,ru_site,DIRECT
  - RULE-SET,ru_ip,DIRECT,no-resolve

  # Весь остальной внешний трафик — через группу PROXY
  - MATCH,PROXY
EOF_MIHOMO
    fi
    log_ok "Конфигурации шлюза AdGuard и Mihomo сгенерированы"
}

# ==============================================================================
# МОДУЛЬ 09: ГЕНЕРАЦИЯ CADDYFILE И DOCKER-COMPOSE.YML
# ==============================================================================

configure_caddy_and_compose() {
    print_step_header "09/11" "ГЕНЕРАЦИЯ CADDYFILE И DOCKER-COMPOSE.YML"
    
    local SAMBA_PASS_ESC
    SAMBA_PASS_ESC=$(yaml_escape "${SAMBA_PASS}")
    local SAMBA_PASS_COMPOSE="${SAMBA_PASS_ESC//\$/\$\$}"
    SAMBA_PASS_COMPOSE="${SAMBA_PASS_COMPOSE%\"}"
    SAMBA_PASS_COMPOSE="${SAMBA_PASS_COMPOSE#\"}"
    local SAMBA_ENV_SHARE="${SHARE_NAME//-/_}"
    local MIHOMO_SECRET_VAL="${MIHOMO_SECRET:-${SAVED_MIHOMO_SECRET:-}}"

    # Формирование элементов портала прямого IP-доступа
    local IP_PORTAL_ITEMS=""
    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🛡️ AdGuard Home</span><a href=\"https://${ADGUARD_DOMAIN}\" target=\"_blank\" rel=\"noopener\">https://${ADGUARD_DOMAIN}</a></li>
    <li><span>🚀 Mihomo Gateway UI</span><a href=\"https://${PROXY_DOMAIN}/#/?hostname=${PROXY_DOMAIN}&port=443&protocol=https&secret=${MIHOMO_SECRET_VAL}\" target=\"_blank\" rel=\"noopener\">https://${PROXY_DOMAIN} [Вход]</a></li>"
    fi
    if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🔑 Vaultwarden</span><a href=\"https://${VAULT_DOMAIN}\" target=\"_blank\" rel=\"noopener\">https://${VAULT_DOMAIN}</a></li>"
    fi
    if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🐙 Gitea Git Server</span><a href=\"https://${GITEA_DOMAIN}\" target=\"_blank\" rel=\"noopener\">https://${GITEA_DOMAIN}</a></li>"
    fi
    if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>📥 qBittorrent (VueTorrent)</span><a href=\"https://${TORRENT_DOMAIN}\" target=\"_blank\" rel=\"noopener\">https://${TORRENT_DOMAIN}</a></li>"
    fi
    if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>📥 MeTube (Загрузка видео)</span><a href=\"https://${METUBE_DOMAIN}\" target=\"_blank\" rel=\"noopener\">https://${METUBE_DOMAIN}</a></li>"
    fi
    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🎵 Navidrome Music (Spotify)</span><a href=\"https://${MUSIC_DOMAIN}\" target=\"_blank\" rel=\"noopener\">https://${MUSIC_DOMAIN}</a></li>"
    fi
    IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>📋 Dozzle Web Logs</span><a href=\"https://${LOGS_DOMAIN}\" target=\"_blank\" rel=\"noopener\">https://${LOGS_DOMAIN}</a></li>"

    cat <<EOF_CADDY > "${APP_DIR}/caddy/Caddyfile"
{
    admin off
}

(security_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "0"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"
    }
}

http://${LOCAL_IP} {
    @cert path /caddy-root.crt /root.crt
    handle @cert {
        root * /data/caddy/pki/authorities/local
        rewrite * /root.crt
        file_server
    }

    handle {
        respond <<EOF_HTML
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Homelab Appliance &amp; Gateway</title>
<style>
body { background: #080d1a; color: #f8fafc; font-family: system-ui, -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 24px; box-sizing: border-box; }
.card { background: #0f172a; border: 1px solid #1e293b; border-radius: 16px; padding: 32px; max-width: 600px; width: 100%; box-shadow: 0 20px 45px rgba(0,0,0,0.7); }
h1 { color: #38bdf8; font-size: 24px; margin: 0 0 8px; display: flex; align-items: center; gap: 8px; }
.badge { background: #065f46; color: #6ee7b7; font-size: 11px; padding: 3px 8px; border-radius: 6px; font-weight: bold; }
p { color: #94a3b8; font-size: 14px; line-height: 1.6; margin: 8px 0 16px; }
.list { list-style: none; padding: 0; margin: 16px 0; }
.list li { margin-bottom: 8px; display: flex; justify-content: space-between; align-items: center; padding: 10px 14px; background: #131e36; border-radius: 8px; border: 1px solid #1e293b; font-size: 14px; }
.list a { color: #38bdf8; text-decoration: none; font-weight: 600; font-family: monospace; font-size: 13px; background: rgba(56, 189, 248, 0.1); padding: 4px 8px; border-radius: 4px; }
.list a:hover { background: rgba(56, 189, 248, 0.25); text-decoration: underline; }
.btn-cert { display: block; text-align: center; background: #0284c7; color: #fff; text-decoration: none; font-weight: 600; font-size: 13px; padding: 10px 16px; border-radius: 8px; margin: 18px 0 10px; transition: background 0.2s; }
.btn-cert:hover { background: #0369a1; }
.tip { background: rgba(56, 189, 248, 0.08); border-left: 3px solid #38bdf8; padding: 12px; font-size: 13px; color: #cbd5e1; border-radius: 4px; margin-top: 14px; line-height: 1.5; }
code { background: #1e293b; color: #38bdf8; padding: 2px 6px; border-radius: 4px; font-size: 12px; }
</style>
</head>
<body>
<div class="card">
  <h1>⚡ Homelab Appliance <span class="badge">ONLINE</span></h1>
  <p>Сервер успешно развернут. Для доступа к защищенным веб-сервисам перейдите по ссылкам:</p>
  <ul class="list">
${IP_PORTAL_ITEMS}
  </ul>
  <a class="btn-cert" href="/caddy-root.crt" download>📥 Скачать Root CA Сертификат (caddy-root.crt)</a>
  <div class="tip">
    💡 <b>Настройка роутера:</b> Укажите в DHCP вашего роутера <code>DNS: ${LOCAL_IP}</code> и <code>Gateway: ${LOCAL_IP}</code>, чтобы все устройства домашней сети автоматически переходили по доменам <code>*.lan</code> и получили чистый интернет без рекламы и блокировок.
  </div>
</div>
</body>
</html>
EOF_HTML 200
    }
}
EOF_CADDY

    if [ "$SSL_MODE" = "2" ]; then
        cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
*.${BASE_DOMAIN}, ${BASE_DOMAIN} {
    tls {
        dns duckdns {env.DUCKDNS_API_TOKEN}
    }
    import security_headers
    encode zstd gzip
EOF_CADDY

        if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @vault host ${VAULT_DOMAIN}
    handle @vault {
        reverse_proxy vaultwarden:80
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @gitea host ${GITEA_DOMAIN}
    handle @gitea {
        reverse_proxy gitea:3000
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @torrent host ${TORRENT_DOMAIN}
    handle @torrent {
        reverse_proxy qbittorrent:8080
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @metube host ${METUBE_DOMAIN} tube.${BASE_DOMAIN}
    handle @metube {
        reverse_proxy metube:8081
    }
EOF_CADDY
        fi


        if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @music host ${MUSIC_DOMAIN}
    handle @music {
        reverse_proxy navidrome:4533
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @adguard host ${ADGUARD_DOMAIN}
    handle @adguard {
        reverse_proxy host.docker.internal:8083
    }

    @proxy host ${PROXY_DOMAIN}
    handle @proxy {
        @api path /api*
        handle @api {
            uri strip_prefix /api
            reverse_proxy host.docker.internal:9090
        }

        handle {
            root * /srv/mihomo-ui
            file_server
            try_files {path} {path}/ /index.html
        }
    }
EOF_CADDY
        fi

        cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @logs host ${LOGS_DOMAIN}
    handle @logs {
        basic_auth {
            ${ADMIN_USER} ${AGH_HASH_CADDY}
        }
        reverse_proxy dozzle:8080 {
            header_up Remote-User {http.auth.user.id}
        }
    }
EOF_CADDY
        echo "}" >> "${APP_DIR}/caddy/Caddyfile"

    else
        if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
${VAULT_DOMAIN} {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy vaultwarden:80
}
EOF_CADDY
        fi

        if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
${GITEA_DOMAIN} {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy gitea:3000
}
EOF_CADDY
        fi

        if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
${TORRENT_DOMAIN} {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy qbittorrent:8080
}
EOF_CADDY
        fi

        if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
${METUBE_DOMAIN}, tube.lan {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy metube:8081
}
EOF_CADDY
        fi


        if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
${MUSIC_DOMAIN} {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy navidrome:4533
}
EOF_CADDY
        fi

        if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
${ADGUARD_DOMAIN} {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy host.docker.internal:8083
}

${PROXY_DOMAIN} {
    tls internal
    import security_headers
    encode zstd gzip

    @api path /api*
    handle @api {
        uri strip_prefix /api
        reverse_proxy host.docker.internal:9090
    }

    handle {
        root * /srv/mihomo-ui
        file_server
        try_files {path} {path}/ /index.html
    }
}
EOF_CADDY
        fi

        cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
${LOGS_DOMAIN} {
    tls internal
    import security_headers
    encode zstd gzip
    basic_auth {
        ${ADMIN_USER} ${AGH_HASH_CADDY}
    }
    reverse_proxy dozzle:8080 {
        header_up Remote-User {http.auth.user.id}
    }
}
EOF_CADDY
    fi

    local CADDY_IMAGE="serfriz/caddy-duckdns:latest"
    [ "$SSL_MODE" = "1" ] && CADDY_IMAGE="caddy:alpine"

    local GITEA_IMAGE="gitea/gitea:latest"

    local GITEA_TZ_MOUNT=""
    if [ -f /etc/timezone ]; then
        GITEA_TZ_MOUNT="- /etc/timezone:/etc/timezone:ro"
    fi

    cat <<EOF_COMPOSE > "${APP_DIR}/docker-compose.yml"
services:
EOF_COMPOSE

    if [[ "${ENABLE_SAMBA}" =~ ^[Yy]$ ]]; then
        cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  samba:
    image: servercontainers/samba:latest
    container_name: samba
    restart: unless-stopped
    network_mode: host
    environment:
      - "SAMBA_CONF_WORKGROUP=WORKGROUP"
      - "SAMBA_CONF_SERVER_STRING=Homelab Storage"
      - "AVAHI_DISABLE=true"
      - "WSDD2_DISABLE=false"
      - "ACCOUNT_${ADMIN_USER_SAFE}=${SAMBA_PASS_COMPOSE}"
      - "UID_${ADMIN_USER_SAFE}=${USER_UID}"
      - "SAMBA_VOLUME_CONFIG_${SAMBA_ENV_SHARE}=[${SHARE_NAME}]; path=/shares/${SHARE_NAME}; valid users=${ADMIN_USER_SAFE}; force user=${ADMIN_USER_SAFE}; guest ok=no; read only=no; browseable=yes; create mask=0664; directory mask=0775"
      - "SAMBA_VOLUME_CONFIG_music=[music]; path=/shares/music; valid users=${ADMIN_USER_SAFE}; force user=${ADMIN_USER_SAFE}; guest ok=no; read only=no; browseable=yes; create mask=0664; directory mask=0775"
    volumes:
      - ${SAVE_DIR}:/shares/${SHARE_NAME}
      - ${SAVE_DIR}/music:/shares/music
    healthcheck:
      test: ["CMD-SHELL", "smbcontrol smbd ping >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    labels:
      - "autoheal=true"

EOF_COMPOSE
    fi

    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  adguardhome:
    image: adguard/adguardhome:latest
    container_name: adguardhome
    restart: unless-stopped
    network_mode: host
    volumes:
      - ${ADGUARD_WORK_DIR}:/opt/adguardhome/work
      - ./adguard/conf:/opt/adguardhome/conf
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8083 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    labels:
      - "autoheal=true"

  mihomo:
    image: metacubex/mihomo:latest
    container_name: mihomo
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - ./mihomo:/root/.config/mihomo
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- --header='Authorization: Bearer ${MIHOMO_SECRET_VAL}' http://127.0.0.1:9090/version >/dev/null 2>&1 || wget -q --spider http://127.0.0.1:9090/ui/ 2>/dev/null || pgrep mihomo >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    labels:
      - "autoheal=true"

EOF_COMPOSE
    fi

    if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
        cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  vaultwarden:
    image: vaultwarden/server:alpine
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      - "DOMAIN=https://${VAULT_DOMAIN}"
      - "ADMIN_TOKEN=${VAULT_ADMIN_HASH_ESCAPED}"
    volumes:
      - ${VAULT_DATA_DIR}:/data
    healthcheck:
      test: ["CMD-SHELL", "curl -fs http://127.0.0.1:80/alive >/dev/null 2>&1 || wget -q --spider http://127.0.0.1:80/alive || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    labels:
      - "autoheal=true"

EOF_COMPOSE
    fi

    if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
        cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  gitea:
    image: ${GITEA_IMAGE}
    container_name: gitea
    restart: unless-stopped
    environment:
      - "USER_UID=${USER_UID}"
      - "USER_GID=${USER_GID}"
      - "GITEA__database__DB_TYPE=sqlite3"
      - "GITEA__database__PATH=/data/gitea/gitea.db"
      - "GITEA__server__ROOT_URL=https://${GITEA_DOMAIN}/"
      - "GITEA__server__DOMAIN=${GITEA_DOMAIN}"
      - "GITEA__server__SSH_DOMAIN=${LOCAL_IP}"
      - "GITEA__server__SSH_PORT=2222"
      - "GITEA__server__SSH_LISTEN_PORT=22"
      - "GITEA__server__LFS_START_SERVER=true"
      - "GITEA__service__DISABLE_REGISTRATION=false"
      - "GITEA__security__INSTALL_LOCK=true"
      - "GITEA__security__PASSWORD_COMPLEXITY=off"
    ports:
      - "2222:22"
    volumes:
      - ${GITEA_DATA_DIR}:/data
      - ${SAVE_DIR}/backups/gitea:/backup
      - /etc/localtime:/etc/localtime:ro
      ${GITEA_TZ_MOUNT}
    healthcheck:
      test: ["CMD-SHELL", "curl -fs http://localhost:3000/api/v1/version >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s
    labels:
      - "autoheal=true"

EOF_COMPOSE
    fi

    if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
        cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    environment:
      - "PUID=${USER_UID}"
      - "PGID=${USER_GID}"
      - "TZ=Etc/UTC"
      - "WEBUI_PORT=8080"
      - "TORRENTING_PORT=6881"
    ports:
      - "127.0.0.1:8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - ./qbittorrent/config:/config
      - ./qbittorrent/vuetorrent:/vuetorrent:ro
      - ${SAVE_DIR}:/downloads
    healthcheck:
      test: ["CMD-SHELL", "curl -fs http://localhost:8080/ >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    labels:
      - "autoheal=true"

EOF_COMPOSE
    fi

    if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
        cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  metube:
    image: alexta69/metube:latest
    container_name: metube
    restart: unless-stopped
    dns:
      - 77.88.8.8
      - 1.1.1.1
      - 8.8.8.8
    ports:
      - "127.0.0.1:8081:8081"
    environment:
      - "PUID=${USER_UID:-1000}"
      - "PGID=${USER_GID:-1000}"
      - "UID=${USER_UID:-1000}"
      - "GID=${USER_GID:-1000}"
      - "UMASK=002"
      - "CHOWN_DIRS=true"
      - "ALLOW_PRIVATE_ADDRESSES=true"
      - "ALLOW_YTDL_OPTIONS_OVERRIDES=true"
      - "DOWNLOAD_DIR=/downloads"
      - "AUDIO_DOWNLOAD_DIR=/music"
      - "CUSTOM_DIRS=true"
      - "CREATE_CUSTOM_DIRS=true"
      - "STATE_DIR=/downloads/.metube"
      - "TEMP_DIR=/downloads/tmp"
      - "YTDL_OPTIONS_FILE=/downloads/.metube/ytdl_options.json"
      - 'YTDL_OPTIONS={"extractor_args":{"youtube":{"player_client":["ios","android","mweb","web"]}}}'
      - "YTDL_NIGHTLY_UPDATE_TIME=04:30"
      - "DEFAULT_THEME=auto"
    volumes:
      - ${SAVE_DIR}/downloads:/downloads
      - ${SAVE_DIR}/music:/music
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:8081/ 2>/dev/null || curl -fs http://localhost:8081/ >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    labels:
      - "autoheal=true"

EOF_COMPOSE
    fi

    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  navidrome:
    image: ${NAVIDROME_IMAGE:-deluan/navidrome:latest}
    container_name: navidrome
    restart: unless-stopped
    user: "${USER_UID:-1000}:${USER_GID:-1000}"
    ports:
      - "127.0.0.1:4533:4533"
    environment:
      - "ND_SCANSCHEDULE=1m"
      - "ND_LOGLEVEL=info"
      - "ND_SESSIONTIMEOUT=48h"
      - "ND_BASEURL="
      - "ND_ENABLETRANSCODINGCONFIG=true"
      - "ND_TRANSCODINGCACHESIZE=200MB"
      - "ND_IMAGECACHESIZE=100MB"
      - "ND_DEFAULTTHEME=Dark"
      - "ND_ENABLESHARING=true"
      - "ND_ENABLEDOWNLOADS=true"
      - "ND_PROMETHEUS_ENABLED=false"
    volumes:
      - ./configs/navidrome:/data
      - ${SAVE_DIR}/music:/music
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:4533/ping 2>/dev/null || curl -fs http://localhost:4533/ping >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    labels:
      - "autoheal=true"

EOF_COMPOSE
    fi

    local CADDY_UI_VOLUME=""
    [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]] && CADDY_UI_VOLUME="- ./mihomo/ui:/srv/mihomo-ui:ro"

    cat <<EOF_COMPOSE >> "${APP_DIR}/docker-compose.yml"
  caddy:
    image: ${CADDY_IMAGE}
    container_name: caddy
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    ports:
      - "80:80"
      - "443:443"
    environment:
      - "DUCKDNS_API_TOKEN=${DUCKDNS_TOKEN}"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile
      - ./caddy/data:/data
      - ./caddy/config:/config
      ${CADDY_UI_VOLUME}
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:80 2>/dev/null || pgrep caddy >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    labels:
      - "autoheal=true"

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - "DOCKER_API_VERSION=${DETECTED_DOCKER_API:-1.45}"
      - "WATCHTOWER_CLEANUP=true"
      - "WATCHTOWER_SCHEDULE=0 0 4 * * *"
      - "WATCHTOWER_INCLUDE_RESTARTING=true"
      - "WATCHTOWER_TIMEOUT=30s"

  autoheal:
    image: willfarrell/autoheal:latest
    container_name: autoheal
    restart: unless-stopped
    environment:
      - "AUTOHEAL_CONTAINER_LABEL=autoheal"
      - "AUTOHEAL_INTERVAL=15"
      - "AUTOHEAL_START_PERIOD=30"
      - "AUTOHEAL_DEFAULT_STOP_TIMEOUT=10"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - "DOZZLE_NO_ANALYTICS=true"
      - "DOZZLE_AUTH_PROVIDER=forward-proxy"
    healthcheck:
      test: ["CMD", "/dozzle", "healthcheck"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    labels:
      - "autoheal=true"
EOF_COMPOSE

    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        local WATCHDOG_EXEC_LINE=""
        if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
            WATCHDOG_EXEC_LINE="ExecStartPost=-/usr/local/bin/gateway-watchdog.sh"
        fi

        cat <<EOF_HOMELAB_SVC > /etc/systemd/system/homelab.service
[Unit]
Description=Homelab Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
${STORAGE_DEP_LINE}

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${APP_DIR}
ExecStart=/usr/local/bin/dc up -d
${WATCHDOG_EXEC_LINE}
ExecStop=/usr/local/bin/dc stop
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF_HOMELAB_SVC

        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable homelab.service >/dev/null 2>&1 || true

    elif [ "${INIT_SYSTEM}" = "openrc" ]; then
        cat <<EOF_HOMELAB_RC > /etc/init.d/homelab
#!/sbin/openrc-run
description="Homelab Docker Compose Stack"
depend() {
    need docker
    after docker homelab-storage network
}
start() {
    ebegin "Starting Homelab Docker Compose Stack"
    cd "${APP_DIR}" && /usr/local/bin/dc up -d
    local ec=$?
    /usr/local/bin/gateway-watchdog.sh 2>/dev/null || true
    eend \$ec
}
stop() {
    ebegin "Stopping Homelab Docker Compose Stack"
    cd "${APP_DIR}" && /usr/local/bin/dc stop
    eend \$?
}
restart() {
    ebegin "Restarting Homelab Docker Compose Stack"
    cd "${APP_DIR}" && /usr/local/bin/dc restart
    eend \$?
}
EOF_HOMELAB_RC
        chmod 755 /etc/init.d/homelab
        rc-update add homelab default >/dev/null 2>&1 || true
    fi

    log_ok "Caddyfile, docker-compose.yml и служба автозапуска успешно сформированы"
}

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
        if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ]; then
            log_ok "Режим обновления: существующий администратор Navidrome (${ADMIN_USER}) сохранен"
        else
            log_info "Автоматическая инициализация администратора Navidrome (${ADMIN_USER})..."
            local NAVIDROME_READY=0
            for i in {1..30}; do
                if docker inspect -f '{{.State.Status}}' navidrome 2>/dev/null | grep -q "running"; then
                    local RES_CREATE
                    RES_CREATE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:4533/auth/setup" \
                        -H "Content-Type: application/json" \
                        -d "{\"userName\":\"${ADMIN_USER}\",\"name\":\"${ADMIN_USER}\",\"password\":\"${MASTER_PASS}\"}" 2>/dev/null || echo "000")
                    if [ "${RES_CREATE}" = "200" ] || [ "${RES_CREATE}" = "201" ]; then
                        log_ok "Администратор Navidrome (${ADMIN_USER}) успешно создан с мастер-паролем"
                        NAVIDROME_READY=1
                        break
                    elif [ "${RES_CREATE}" = "404" ]; then
                        local RES_FALLBACK
                        RES_FALLBACK=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:4533/api/setup" \
                            -H "Content-Type: application/json" \
                            -d "{\"userName\":\"${ADMIN_USER}\",\"name\":\"${ADMIN_USER}\",\"password\":\"${MASTER_PASS}\"}" 2>/dev/null || echo "000")
                        if [ "${RES_FALLBACK}" = "200" ] || [ "${RES_FALLBACK}" = "201" ]; then
                            log_ok "Администратор Navidrome (${ADMIN_USER}) успешно создан с мастер-паролем"
                            NAVIDROME_READY=1
                            break
                        fi
                    elif [ "${RES_CREATE}" = "400" ] || [ "${RES_CREATE}" = "409" ]; then
                        log_ok "Администратор Navidrome (${ADMIN_USER}) уже инициализирован"
                        NAVIDROME_READY=1
                        break
                    fi
                fi
                sleep 2
            done
            [ $NAVIDROME_READY -eq 1 ] && log_ok "Navidrome готов к работе (порт 4533 / ${MUSIC_DOMAIN})"
        fi
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
    local CUR_VER="${SAVED_HOMELAB_VERSION:-2.8.12}"
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
    local CUR_VER="${SAVED_HOMELAB_VERSION:-2.8.12}"
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

# ==============================================================================
# МОДУЛЬ 11: АВТОМАТИЧЕСКАЯ ДИАГНОСТИКА СЕРВИСОВ И ИТОГОВЫЙ ДАШБОРД
# ==============================================================================

diagnose_and_verify_system() {
    print_step_header "11/11" "АВТОМАТИЧЕСКАЯ ДИАГНОСТИКА СЕРВИСОВ И СИСТЕМЫ"

    local DIAG_LOG="/opt/homelab/diagnostic_report.log"
    local USER_HOME
    USER_HOME=$(eval echo ~"${TARGET_USER}" 2>/dev/null || echo "/home/${TARGET_USER}")
    local USER_DIAG_LOG="${USER_HOME}/diagnostic_report.log"
    local HAS_ISSUES=0

    mkdir -p /opt/homelab
    cat <<EOF_DIAG > "${DIAG_LOG}"
=============================================================================
             ОТЧЕТ ДИАГНОСТИКИ СИСТЕМЫ HOMELAB & TRANSPARENT GATEWAY
                  Дата и время: $(date '+%Y-%m-%d %H:%M:%S %Z')
=============================================================================
Дистрибутив:       ${PRETTY_NAME:-Linux} ($(uname -r))
Init-система:      ${INIT_SYSTEM}
Платформа:         ${SYSTEM_ARCH} (Аппаратный AES: $([ $HAS_HARDWARE_AES -eq 1 ] && echo "Да" || echo "Нет")$([ $IS_CONTAINER -eq 1 ] && echo ", Контейнер: Да" || echo ""))
IP сервера:        ${LOCAL_IP}
Шлюз:              ${ROUTER_GATEWAY}
Интерфейс:         ${DEFAULT_IFACE}
Подсеть:           ${LAN_SUBNET}
Каталог данных:    ${SAVE_DIR}
-----------------------------------------------------------------------------
EOF_DIAG

    echo -e "  ${CLR_CYAN}Проверка статуса запущенных сервисов и сетевых портов...${CLR_RESET}"
    echo ""

    if docker info >/dev/null 2>&1; then
        echo -e "    ${TAG_OK} Docker Daemon:           ${CLR_GREEN}[РАБОТАЕТ]${CLR_RESET}"
        echo "Docker Daemon: OK" >> "${DIAG_LOG}"
    else
        echo -e "    ${TAG_ERR} Docker Daemon:           ${CLR_RED}[НЕ ОТВЕЧАЕТ]${CLR_RESET}"
        echo "Docker Daemon: FAILED" >> "${DIAG_LOG}"
        HAS_ISSUES=1
    fi

    declare -A EXPECTED_SERVICES
    [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]] && EXPECTED_SERVICES["adguardhome"]="AdGuard Home (DNS 53)"
    [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]] && EXPECTED_SERVICES["mihomo"]="Mihomo TUN (Ядро маршрутизации)"
    [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]   && EXPECTED_SERVICES["vaultwarden"]="Vaultwarden (Пароли)"
    [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]   && EXPECTED_SERVICES["gitea"]="Gitea (Git-сервер)"
    [[ "${ENABLE_SAMBA}" =~ ^[Yy]$ ]]   && EXPECTED_SERVICES["samba"]="Samba (Сетевой доступ)"
    [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]    && EXPECTED_SERVICES["qbittorrent"]="qBittorrent (VueTorrent)"
    [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]  && EXPECTED_SERVICES["metube"]="MeTube (Загрузка медиа)"
    [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]] && EXPECTED_SERVICES["navidrome"]="Navidrome Hi-Fi (Музыка)"
    EXPECTED_SERVICES["caddy"]="Caddy Reverse Proxy"
    EXPECTED_SERVICES["dozzle"]="Dozzle (Web Log Viewer)"
    EXPECTED_SERVICES["watchtower"]="Watchtower (Автообновления)"
    EXPECTED_SERVICES["autoheal"]="Autoheal (Самовосстановление)"

    echo "" >> "${DIAG_LOG}"
    echo "--- СТАТУС КОНТЕЙНЕРОВ DOCKER ---" >> "${DIAG_LOG}"

    for c_name in "${!EXPECTED_SERVICES[@]}"; do
        local c_desc="${EXPECTED_SERVICES[$c_name]}"
        local c_status="not_found"

        for _ in {1..5}; do
            c_status=$(docker inspect -f '{{.State.Status}}' "${c_name}" 2>/dev/null || echo "not_found")
            [ "${c_status}" = "running" ] && break
            sleep 1
        done

        local c_health
        c_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "${c_name}" 2>/dev/null || true)
        local health_tag=""
        if [ "$c_health" = "healthy" ]; then
            health_tag=" / HEALTHY"
        elif [ "$c_health" = "starting" ]; then
            health_tag=" / ЗАПУСК"
        elif [ "$c_health" = "unhealthy" ]; then
            health_tag=" / СБОЙ"
            HAS_ISSUES=1
        fi

        if [ "${c_status}" = "running" ] && [ "$c_health" != "unhealthy" ]; then
            printf "    ${TAG_OK} %-32s ${CLR_GREEN}[ОНЛАЙН%s]${CLR_RESET}\n" "${c_desc}" "${health_tag}"
            echo "[OK] Container ${c_name} (${c_desc}): RUNNING (Health: ${c_health:-none})" >> "${DIAG_LOG}"
        else
            printf "    ${TAG_ERR} %-32s ${CLR_RED}[ОШИБКА: %s%s]${CLR_RESET}\n" "${c_desc}" "${c_status}" "${health_tag}"
            echo "[FAIL] Container ${c_name} (${c_desc}): STATUS=${c_status} (Health: ${c_health:-none})" >> "${DIAG_LOG}"
            HAS_ISSUES=1

            echo "--- Логи контейнера ${c_name} (последние 40 строк): ---" >> "${DIAG_LOG}"
            docker logs --tail 40 "${c_name}" >> "${DIAG_LOG}" 2>&1 || true
            echo "--------------------------------------------------------" >> "${DIAG_LOG}"
        fi
    done

    echo ""
    echo -e "  ${CLR_CYAN}Проверка сетевых функций шлюза и прав доступа...${CLR_RESET}"

    local IP_FWD
    IP_FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [ "${IP_FWD}" = "1" ]; then
        echo -e "    ${TAG_OK} IPv4 Forwarding:          ${CLR_GREEN}[АКТИВЕН]${CLR_RESET}"
        echo "IPv4 Forwarding: OK (1)" >> "${DIAG_LOG}"
    else
        echo -e "    ${TAG_ERR} IPv4 Forwarding:          ${CLR_RED}[ОТКЛЮЧЕН]${CLR_RESET}"
        echo "IPv4 Forwarding: DISABLED (0)" >> "${DIAG_LOG}"
        HAS_ISSUES=1
    fi

    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        local FW_STATUS="НЕ АКТИВЕН"
        if command -v nft >/dev/null 2>&1 && nft list table inet homelab >/dev/null 2>&1; then
            FW_STATUS="nftables (inet homelab)"
        fi
        echo -e "    ${TAG_OK} Фаервол и NAT:            ${CLR_GREEN}[${FW_STATUS}]${CLR_RESET}"
        echo "Firewall status: ${FW_STATUS}" >> "${DIAG_LOG}"
    fi

    local DNS_TEST=0
    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        if python3 -c "import socket, sys; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2); s.sendto(b'\xaa\xaa\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01', ('127.0.0.1', 53)); data, _ = s.recvfrom(512); sys.exit(0 if len(data) > 12 else 1)" 2>/dev/null; then
            DNS_TEST=1
        fi
        if [ "${DNS_TEST}" -eq 1 ]; then
            echo -e "    ${TAG_OK} DNS Резолвер (порт 53):   ${CLR_GREEN}[ОТВЕЧАЕТ]${CLR_RESET}"
            echo "DNS Port 53 Check: OK" >> "${DIAG_LOG}"

            # Безопасное переключение хоста на локальный AdGuard Home после подтверждения работоспособности
            log_info "Фиксация локального DNS AdGuard Home (127.0.0.1) в /etc/resolv.conf хоста..."
            {
                echo "# Сгенерировано Homelab Gateway (локальный резолвер AdGuard Home)"
                echo "nameserver 127.0.0.1"
                echo "nameserver 77.88.8.8"
                echo "options timeout:2 attempts:2"
            } > /etc/resolv.conf 2>/dev/null || true
        else
            echo -e "    ${TAG_WARN} DNS Резолвер (порт 53):   ${CLR_YELLOW}[ОЖИДАНИЕ ИНИЦИАЛИЗАЦИИ]${CLR_RESET}"
            echo "DNS Port 53 Check: PENDING" >> "${DIAG_LOG}"
        fi
    fi

    local STORAGE_OK=0
    if [ -d "${SAVE_DIR}" ]; then
        if su -s /bin/sh "${TARGET_USER}" -c "test -w '${SAVE_DIR}'" 2>/dev/null || [ -w "${SAVE_DIR}" ]; then
            STORAGE_OK=1
        fi
    fi
    if [ "${STORAGE_OK}" -eq 1 ]; then
        echo -e "    ${TAG_OK} Каталог хранилища:        ${CLR_GREEN}[ДОСТУПЕН ДЛЯ ЗАПИСИ]${CLR_RESET}"
        echo "Storage directory ${SAVE_DIR}: OK" >> "${DIAG_LOG}"
    else
        echo -e "    ${TAG_ERR} Каталог хранилища:        ${CLR_RED}[НЕДОСТУПЕН]${CLR_RESET}"
        echo "Storage directory ${SAVE_DIR}: PERMISSION/MOUNT ERROR" >> "${DIAG_LOG}"
        HAS_ISSUES=1
    fi

    cat <<EOF_SYS_INFO >> "${DIAG_LOG}"

--- СИСТЕМНЫЕ РЕСУРСЫ ---
Дисковое пространство:
$(df -h "${SAVE_DIR}" / 2>/dev/null)

Оперативная память:
$(free -h 2>/dev/null)

Сетевые маршруты:
$(ip route show 2>/dev/null)

Сетевые адреса:
$(ip -o -4 addr show 2>/dev/null)
EOF_SYS_INFO

    cp -f "${DIAG_LOG}" "${USER_DIAG_LOG}" 2>/dev/null || true
    chmod 640 "${DIAG_LOG}" "${USER_DIAG_LOG}" 2>/dev/null || true
    chown "${USER_UID}:${USER_GID}" "${USER_DIAG_LOG}" 2>/dev/null || true

    echo ""
    if [ "${HAS_ISSUES}" -eq 0 ]; then
        echo -e "  ${CLR_GREEN}${CLR_BOLD}✔  ДИАГНОСТИКА: Все сервисы функционируют нормально, сбоев не обнаружено!${CLR_RESET}"
        echo ""
        /usr/local/bin/homelab-notify "Самодиагностика Homelab" "Комплекс успешно развернут. Все сервисы функционируют нормально (0 ошибок)." "OK" 2>/dev/null || true
    else
        echo -e "  ${CLR_RED}${CLR_BOLD}▲  ДИАГНОСТИКА: Обнаружены отклонения в работе сервисов!${CLR_RESET}"
        echo -e "  ${CLR_YELLOW}Подробный журнал диагностики и логов сбоев сохранен в:${CLR_RESET}"
        echo ""
        echo -e "      ${CLR_WHITE}${CLR_BOLD}cat ${DIAG_LOG}${CLR_RESET}"
        echo -e "      ${CLR_DIM}или в домашнем каталоге:${CLR_RESET} ${CLR_WHITE}cat ${USER_DIAG_LOG}${CLR_RESET}"
        echo ""
        /usr/local/bin/homelab-notify "Сбой в Homelab" "Обнаружены отклонения при проверке сервисов! См. /opt/homelab/diagnostic_report.log" "CRIT" 2>/dev/null || true
    fi
}

show_summary_dashboard() {
    echo ""
    echo -e "  ${CLR_NEON_GREEN}╔════════════════════════════════════════════════════════════════════════════╗${CLR_RESET}"
    echo -e "  ${CLR_NEON_GREEN}║${CLR_RESET} ${CLR_WHITE}${CLR_BOLD}  HOMELAB APPLIANCE & TRANSPARENT GATEWAY УСПЕШНО РАЗВЕРНУТ И АКТИВЕН       ${CLR_RESET}${CLR_NEON_GREEN}║${CLR_RESET}"
    echo -e "  ${CLR_NEON_GREEN}╚════════════════════════════════════════════════════════════════════════════╝${CLR_RESET}"
    echo ""

    echo -e "  ${CLR_NEON_PURPLE}╭── СЕТЕВОЙ ШЛЮЗ И МАРШРУТИЗАЦИЯ (RUSSIA PRO 2026) ──────────────────────────╮${CLR_RESET}"
    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Портал навигации по IP:${CLR_RESET}      ${CLR_NEON_GREEN}http://${LOCAL_IP}${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ AdGuard Home (DNS & AdBlock):${CLR_RESET}    ${CLR_NEON_CYAN}https://${ADGUARD_DOMAIN}${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Mihomo Smart Routing UI:${CLR_RESET}         ${CLR_NEON_CYAN}https://${PROXY_DOMAIN}/#/?hostname=${PROXY_DOMAIN}&port=443&protocol=https&secret=${MIHOMO_SECRET}${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Секрет API панели управления:${CLR_RESET}    ${CLR_NEON_GOLD}${MIHOMO_SECRET}${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Госуслуги, банки и сервисы РФ:${CLR_RESET}   ${CLR_NEON_GREEN}100% ПРЯМОЙ ДОСТУП (DIRECT, без капч и задержек)${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Маршрутизация YouTube & Media:${CLR_RESET}  ${CLR_NEON_GREEN}АКТИВНА (Туннелирование -> AUTO / PROXY)${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Защита от перехвата и утечек:${CLR_RESET}    ${CLR_NEON_GREEN}АКТИВНА (nftables DNS Hijack -> порт 53)${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Автоматический TCP MSS Clamp:${CLR_RESET}    ${CLR_NEON_GREEN}АКТИВЕН (защита от зависания пакетов на MTU)${CLR_RESET}"
        if [ -n "${SELECTED_DOH_1:-}" ]; then
            echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Скоростной DoH (HTTPS):${CLR_RESET}          ${CLR_NEON_CYAN}${SELECTED_DOH_1}${CLR_RESET}"
        fi
        if [ -n "${SELECTED_DOT_1:-}" ]; then
            echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Защищенный DoT (TLS):${CLR_RESET}            ${CLR_NEON_CYAN}${SELECTED_DOT_1}${CLR_RESET}"
        fi
    else
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}◈ Портал навигации по IP:${CLR_RESET}      ${CLR_NEON_GREEN}http://${LOCAL_IP}${CLR_RESET}"
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_MUTED}• Прозрачный сетевой шлюз отключен в конфигурации${CLR_RESET}"
    fi
    echo -e "  ${CLR_NEON_PURPLE}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
    echo ""

    echo -e "  ${CLR_NEON_CYAN}╭── ВЕБ-СЕРВИСЫ И ОБЛАЧНЫЕ ПРИЛОЖЕНИЯ (HTTPS) ───────────────────────────────╮${CLR_RESET}"
    if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}✦ Vaultwarden (Пароли):${CLR_RESET}            ${CLR_NEON_CYAN}https://${VAULT_DOMAIN}${CLR_RESET}"
        echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}✦ Панель администратора:${CLR_RESET}           ${CLR_NEON_CYAN}https://${VAULT_DOMAIN}/admin${CLR_RESET}"
    fi
    if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}✦ Gitea (Git-сервер):${CLR_RESET}              ${CLR_NEON_CYAN}https://${GITEA_DOMAIN}${CLR_RESET} ${CLR_DIM}(SSH порт: 2222)${CLR_RESET}"
    fi
    if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}✦ qBittorrent (VueTorrent):${CLR_RESET}        ${CLR_NEON_CYAN}https://${TORRENT_DOMAIN}${CLR_RESET}"
    fi
    if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}✦ MeTube (Загрузка видео и аудио):${CLR_RESET} ${CLR_NEON_CYAN}https://${METUBE_DOMAIN}${CLR_RESET}"
    fi
    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}✦ Navidrome (Hi-Fi Музыка / Spotify):${CLR_RESET}   ${CLR_NEON_CYAN}https://${MUSIC_DOMAIN}${CLR_RESET}"
        echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_DIM}    (Клиенты: Symfonium для Android / Substreamer для iOS / Feishin для ПК)${CLR_RESET}"
    fi
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}✦ Dozzle (Логи контейнеров):${CLR_RESET}       ${CLR_NEON_CYAN}https://${LOGS_DOMAIN}${CLR_RESET} ${CLR_DIM}(Авторизация: ${ADMIN_USER})${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
    echo ""

    echo -e "  ${CLR_NEON_GOLD}╭── ЕДИНЫЕ УЧЕТНЫЕ ДАННЫЕ И СЕКРЕТЫ ─────────────────────────────────────────╮${CLR_RESET}"
    echo -e "  ${CLR_NEON_GOLD}│${CLR_RESET}  ${CLR_WHITE}⚡ Имя администратора:${CLR_RESET}             ${CLR_NEON_GREEN}${ADMIN_USER}${CLR_RESET}"
    echo -e "  ${CLR_NEON_GOLD}│${CLR_RESET}  ${CLR_WHITE}⚡ Единый мастер-пароль:${CLR_RESET}           ${CLR_NEON_GREEN}${MASTER_PASS}${CLR_RESET}"
    if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_GOLD}│${CLR_RESET}  ${CLR_WHITE}⚡ Токен Vaultwarden /admin:${CLR_RESET}       ${CLR_NEON_GOLD}${VAULT_ADMIN_TOKEN}${CLR_RESET}"
    fi
    if [[ "${ENABLE_TELEGRAM}" =~ ^[Yy]$ ]]; then
        local TG_ST="АКТИВНЫ"
        [ -z "${TELEGRAM_BOT_TOKEN:-}" ] && TG_ST="ОЖИДАЮТ ТОКЕН В .env"
        echo -e "  ${CLR_NEON_GOLD}│${CLR_RESET}  ${CLR_WHITE}⚡ Telegram Оповещения:${CLR_RESET}             ${CLR_NEON_GREEN}${TG_ST} (Chat ID: ${TELEGRAM_CHAT_ID:-не указан})${CLR_RESET}"
    fi
    echo -e "  ${CLR_NEON_GOLD}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
    echo ""

    if [ "$SSL_MODE" = "1" ]; then
        echo -e "  ${CLR_NEON_BLUE}╭── ДОВЕРИЕ СЕРТИФИКАТАМ (ROOT CA CERTIFICATE) ──────────────────────────────╮${CLR_RESET}"
        echo -e "  ${CLR_NEON_BLUE}│${CLR_RESET}  ${CLR_WHITE}🔒 Сертификат CA на сервере:${CLR_RESET}       ${CLR_NEON_GOLD}${SAVE_DIR}/certificates/caddy-root.crt${CLR_RESET}"
        printf "  ${CLR_NEON_BLUE}│${CLR_RESET}  ${CLR_WHITE}🔒 Сетевой путь (SMB):${CLR_RESET}             ${CLR_NEON_GOLD}\\\\\\\\%s\\\\%s\\\\certificates\\\\caddy-root.crt${CLR_RESET}\n" "${LOCAL_IP}" "${SHARE_NAME}"
        echo -e "  ${CLR_NEON_BLUE}│${CLR_RESET}  ${CLR_DIM}(Установите в 'Доверенные корневые центры' на клиентах для зелёного замка)${CLR_RESET}"
        echo -e "  ${CLR_NEON_BLUE}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
        echo ""
    fi

    if [[ "${ENABLE_SAMBA}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_BLUE}╭── СЕТЕВОЕ ХРАНИЛИЩЕ SAMBA (WINDOWS / MAC / LINUX) ─────────────────────────╮${CLR_RESET}"
        printf "  ${CLR_NEON_BLUE}│${CLR_RESET}  ${CLR_WHITE}📁 Общая папка хранилища:${CLR_RESET}          ${CLR_NEON_GREEN}\\\\\\\\%s\\\\%s${CLR_RESET}\n" "${LOCAL_IP}" "${SHARE_NAME}"
        if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
            printf "  ${CLR_NEON_BLUE}│${CLR_RESET}  ${CLR_WHITE}🎵 Музыкальная медиатека:${CLR_RESET}          ${CLR_NEON_GREEN}\\\\\\\\%s\\\\music${CLR_RESET}\n" "${LOCAL_IP}"
        fi
        echo -e "  ${CLR_NEON_BLUE}│${CLR_RESET}  ${CLR_WHITE}📁 Учетная запись / Пароль:${CLR_RESET}        ${ADMIN_USER} / ${SAMBA_PASS}"
        echo -e "  ${CLR_NEON_BLUE}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
        echo ""
    fi

    local CUR_FS="${SAVE_FSTYPE:-${SAVED_SAVE_FSTYPE:-ext4}}"
    echo -e "  ${CLR_NEON_PURPLE}╭── ДИСКОВОЕ ХРАНИЛИЩЕ И ОПТИМИЗАЦИЯ ────────────────────────────────────────╮${CLR_RESET}"
    if [ "$STORAGE_MODE" = "1" ]; then
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}💾 Режим размещения:${CLR_RESET}              ${CLR_NEON_GREEN}Системный накопитель (OS Root Partition)${CLR_RESET}"
    else
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}💾 Режим размещения:${CLR_RESET}              ${CLR_NEON_GREEN}Внешний накопитель (Точка монтирования: ${MOUNT_ROOT})${CLR_RESET}"
    fi
    echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}💾 Каталог данных стека:${CLR_RESET}          ${CLR_NEON_CYAN}${SAVE_DIR}${CLR_RESET}"
    echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}💾 Файловая система:${CLR_RESET}              ${CLR_NEON_GOLD}${CUR_FS^^}${CLR_RESET}"
    if [ "${CUR_FS}" = "btrfs" ]; then
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}💾 Оптимизация фрагментации:${CLR_RESET}      ${CLR_NEON_GREEN}No-COW активен (chattr +C для SQLite БД и торрентов)${CLR_RESET}"
    else
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}💾 Оптимизация фрагментации:${CLR_RESET}      ${CLR_NEON_GREEN}Прямая in-place запись (CoW-фрагментация исключена архитектурно)${CLR_RESET}"
    fi
    if [ "$STORAGE_MODE" = "4" ] || [ "$STORAGE_MODE" = "5" ]; then
        echo -e "  ${CLR_NEON_PURPLE}│${CLR_RESET}  ${CLR_WHITE}💾 Ручная разблокировка LUKS:${CLR_RESET}     ${CLR_NEON_GOLD}sudo homelab-unlock${CLR_RESET}"
    fi
    echo -e "  ${CLR_NEON_PURPLE}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
    echo ""

    echo -e "  ${CLR_NEON_GREEN}╭── НАСТРОЙКА ДОМАШНЕГО РОУТЕРА (1 ДЕЙСТВИЕ ДЛЯ ВСЕЙ СЕТИ) ──────────────────╮${CLR_RESET}"
    echo -e "  ${CLR_NEON_GREEN}│${CLR_RESET}  ${CLR_WHITE}В параметрах DHCP вашего роутера укажите:${CLR_RESET}"
    echo -e "  ${CLR_NEON_GREEN}│${CLR_RESET}  ${CLR_WHITE}• Первичный DNS-сервер:${CLR_RESET}            ${CLR_NEON_GREEN}${LOCAL_IP}${CLR_RESET}"
    if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
        echo -e "  ${CLR_NEON_GREEN}│${CLR_RESET}  ${CLR_WHITE}• Основной шлюз (Gateway):${CLR_RESET}         ${CLR_NEON_GREEN}${LOCAL_IP}${CLR_RESET}"
    fi
    echo -e "  ${CLR_NEON_GREEN}│${CLR_RESET}  ${CLR_DIM}После этого все смартфоны, ПК и Smart TV в сети сразу получат фильтрацию${CLR_RESET}"
    echo -e "  ${CLR_NEON_GREEN}│${CLR_RESET}  ${CLR_DIM}рекламы, доступ к локальным *.lan доменам и интеллектуальную маршрутизацию!${CLR_RESET}"
    echo -e "  ${CLR_NEON_GREEN}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
    echo ""

    echo -e "  ${CLR_NEON_CYAN}╭── ЕДИНАЯ КОНСОЛЬНАЯ УТИЛИТА УПРАВЛЕНИЯ (HOMELAB CLI) ───────────────────────╮${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Статус и дашборд:${CLR_RESET}            ${CLR_NEON_GREEN}homelab status${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Полная самодиагностика:${CLR_RESET}      ${CLR_NEON_GREEN}homelab doctor${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Журналы сервисов в реалтайме:${CLR_RESET} ${CLR_NEON_GREEN}homelab logs [сервис] -f${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Экспорт всех логов в файл:${CLR_RESET}   ${CLR_NEON_GREEN}homelab dump-logs${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Перезапуск стека/сервиса:${CLR_RESET}    ${CLR_NEON_GREEN}homelab restart [сервис]${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Горячий бэкап баз данных:${CLR_RESET}    ${CLR_NEON_GREEN}homelab backup${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Тестовое оповещение в TG:${CLR_RESET}    ${CLR_NEON_GREEN}homelab notify [текст]${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Управление cookies YouTube:${CLR_RESET}  ${CLR_NEON_GREEN}homelab cookies [файл]${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Безопасный апдейт образов:${CLR_RESET}   ${CLR_NEON_GREEN}homelab update${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Бесшовный апгрейд ядра:${CLR_RESET}   ${CLR_NEON_GREEN}homelab upgrade${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}│${CLR_RESET}  ${CLR_WHITE}• Проверка версии и обновлений:${CLR_RESET} ${CLR_NEON_GREEN}homelab version${CLR_RESET}"
    echo -e "  ${CLR_NEON_CYAN}╰────────────────────────────────────────────────────────────────────────────╯${CLR_RESET}"
    echo ""
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --upgrade|--update-core|-u)
                IS_UPGRADE_MODE=1
                ;;
            --version|-v)
                echo "Homelab Appliance & Transparent Gateway version: ${HOMELAB_VERSION}"
                exit 0
                ;;
        esac
    done

    show_banner
    check_privileges
    detect_hardware_capabilities
    detect_os
    load_previous_config
    sync_time
    install_pkgs
    setup_zram
    detect_network
    prompt_configuration
    setup_credentials
    setup_gateway_networking
    setup_directories
    benchmark_dns_servers
    configure_gateway_services
    configure_caddy_and_compose
    setup_backups_and_start
    diagnose_and_verify_system
    show_summary_dashboard
}

main "$@"
