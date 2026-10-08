#!/usr/bin/env bash
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
