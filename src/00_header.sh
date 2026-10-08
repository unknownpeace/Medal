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
#             qBittorrent (VueTorrent WebUI), Telegram Bot (yt-dlp Media Downloader),
#             Caddy (Internal/DuckDNS SSL), Watchtower (Docker API 1.45+)
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
USER_UID=""
USER_GID=""
SAVE_FSTYPE=""

MASTER_PASS=""
MIHOMO_SECRET=""
SAMBA_PASS=""
AGH_PASS=""
VAULT_ADMIN_TOKEN=""
ADMIN_USER=""
ADMIN_USER_SAFE=""
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
ENABLE_METUBE="Y"
ENABLE_NAVIDROME="Y"
ENABLE_TG_BOT="Y"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
METUBE_DOMAIN=""
MUSIC_DOMAIN=""
NAVIDROME_IMAGE="deluan/navidrome:latest"
HOMELAB_VERSION="2.8.2"
HOMELAB_REPO="unknownpeace/Medal"
HOMELAB_RAW_URL="https://raw.githubusercontent.com/${HOMELAB_REPO}/main"
IS_UPGRADE_MODE=0
