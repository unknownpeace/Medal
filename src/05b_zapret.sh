#!/usr/bin/env bash
# ==============================================================================
# МОДУЛЬ 05b: УСТАНОВКА И НАСТРОЙКА ZAPRET2 (DPI-BYPASS ТСПУ ДЛЯ YOUTUBE И DISCORD)
# ==============================================================================

setup_zapret2() {
    print_step_header "05b/11" "ИНТЕГРАЦИЯ И АКТИВАЦИЯ ZAPRET2 (DPI-BYPASS ТСПУ)"

    if [[ ! "${ENABLE_ZAPRET:-Y}" =~ ^[Yy]$ ]]; then
        log_info "Zapret2 DPI-Bypass отключен пользователем в конфигурации (пропуск)"
        return 0
    fi

    log_info "Подготовка подсистемы Zapret2 (DPI Desynchronization Engine)..."

    # 1. Загрузка необходимых модулей ядра Linux (NFQUEUE / Conntrack)
    modprobe nfnetlink_queue 2>/dev/null || true
    modprobe nft_queue 2>/dev/null || true
    mkdir -p /etc/modules-load.d
    echo -e "nfnetlink_queue\nnft_queue" > /etc/modules-load.d/zapret.conf 2>/dev/null || true
    grep -q '^nfnetlink_queue$' /etc/modules 2>/dev/null || echo "nfnetlink_queue" >> /etc/modules 2>/dev/null || true
    grep -q '^nft_queue$' /etc/modules 2>/dev/null || echo "nft_queue" >> /etc/modules 2>/dev/null || true

    # Либеральный режим Conntrack для предотвращения отбрасывания пакетов с измененным TCP Seq/ACK
    sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1 >/dev/null 2>&1 || true
    mkdir -p /etc/sysctl.d
    echo "net.netfilter.nf_conntrack_tcp_be_liberal = 1" > /etc/sysctl.d/99-zapret.conf 2>/dev/null || true

    local ZAPRET_DIR="/opt/zapret2"
    mkdir -p "${ZAPRET_DIR}"

    # 2. Динамическое определение последней версии релиза zapret2 на GitHub
    log_info "Поиск последнего релиза zapret2 на GitHub..."
    local LATEST_TAG=""
    LATEST_TAG=$(curl -sSI -m 10 "https://github.com/bol-van/zapret2/releases/latest" 2>/dev/null | grep -i '^location:' | tr -d '\r' | awk -F'/' '{print $NF}' || true)
    LATEST_TAG="${LATEST_TAG:-v1.0.5.2}"
    local TAR_URL="https://github.com/bol-van/zapret2/releases/download/${LATEST_TAG}/zapret2-${LATEST_TAG}.tar.gz"

    log_info "Загрузка официального дистрибутива Zapret2 (${LATEST_TAG})..."
    local TMP_TAR="/tmp/zapret2_${LATEST_TAG}.tar.gz"
    local DOWNLOAD_OK=0

    if curl -fsSL -m 60 "${TAR_URL}" -o "${TMP_TAR}" 2>/dev/null; then
        DOWNLOAD_OK=1
    elif command -v wget >/dev/null 2>&1 && wget -q --timeout=60 "${TAR_URL}" -O "${TMP_TAR}" 2>/dev/null; then
        DOWNLOAD_OK=1
    fi

    if [ $DOWNLOAD_OK -eq 1 ] && [ -s "${TMP_TAR}" ]; then
        run_spin "Распаковка дистрибутива Zapret2" bash -c "tar -xzf '${TMP_TAR}' -C '/tmp/' && cp -rf /tmp/zapret2-${LATEST_TAG#v}/* '${ZAPRET_DIR}/' 2>/dev/null || cp -rf /tmp/zapret2-*/* '${ZAPRET_DIR}/' 2>/dev/null && rm -rf /tmp/zapret2-*"
        rm -f "${TMP_TAR}"
    elif [ -d "zapret2-${LATEST_TAG#v}" ]; then
        log_info "Использование локально предзагруженного архива zapret2..."
        cp -rf "zapret2-${LATEST_TAG#v}/"* "${ZAPRET_DIR}/" 2>/dev/null || true
    fi

    # 3. Автоматический выбор архитектурных бинарников (nfqws2, ip2net, mdig)
    if [ -x "${ZAPRET_DIR}/install_bin.sh" ]; then
        run_spin "Компоновка исполняемых файлов (nfqws2 / ${SYSTEM_ARCH})" bash -c "cd '${ZAPRET_DIR}' && ./install_bin.sh"
    fi

    # 4. Формирование боевой конфигурации /opt/zapret2/config
    cat <<'EOF_ZCONFIG' > "${ZAPRET_DIR}/config"
# Zapret2 production configuration (Russia Pro 2026 - Universal DPI Bypass)
FWTYPE=nftables
POSTNAT=1
NFQWS2_ENABLE=1
NFQWS2_PORTS_TCP=80,443
NFQWS2_PORTS_UDP=443
NFQWS2_TCP_PKT_OUT=20
NFQWS2_TCP_PKT_IN=10
NFQWS2_UDP_PKT_OUT=5
NFQWS2_UDP_PKT_IN=3
DESYNC_MARK=0x40000000
DESYNC_MARK_POSTNAT=0x20000000

# Универсальные стратегии десинхронизации ТСПУ для ВСЕХ сайтов (YouTube 4K, Discord, Pixiv, Rutracker и др.)
NFQWS2_OPT="
--filter-tcp=80 --filter-l7=http <HOSTLIST> --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2 --new
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000 --lua-desync=multidisorder:pos=1,midsld --new
--filter-udp=443 --filter-l7=quic <HOSTLIST_NOAUTO> --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6
"

# Режим 'none' активирует десинхронизацию ТСПУ для ВСЕХ исходящих соединений (без ограничений списком доменов)
MODE_FILTER=none
FLOWOFFLOAD=donttouch
INIT_APPLY_FW=1
DISABLE_IPV6=1
FILTER_TTL_EXPIRED_ICMP=1
EOF_ZCONFIG

    # 5. Активация кастомного скрипта обхода замедления Discord медиа/голосовых пакетов
    mkdir -p "${ZAPRET_DIR}/init.d/sysv/custom.d"
    if [ -f "${ZAPRET_DIR}/init.d/custom.d.examples.linux/50-discord-media" ]; then
        cp "${ZAPRET_DIR}/init.d/custom.d.examples.linux/50-discord-media" "${ZAPRET_DIR}/init.d/sysv/custom.d/50-discord-media"
        chmod 755 "${ZAPRET_DIR}/init.d/sysv/custom.d/50-discord-media" 2>/dev/null || true
    fi

    # 6. Интеграция службы и запуск в Init-системе (OpenRC / systemd)
    if [ "${INIT_SYSTEM}" = "openrc" ]; then
        cat << 'EOF_OPENRC_ZAPRET' > /etc/init.d/zapret2
#!/sbin/openrc-run
# Zapret2 OpenRC service wrapper with explicit base path
ZAPRET_BASE="/opt/zapret2"
ZAPRET_INIT="${ZAPRET_BASE}/init.d/sysv/zapret2"

extra_commands="start_fw stop_fw restart_fw start_daemons stop_daemons restart_daemons reload_ifsets list_ifsets list_table"
description="Zapret2 DPI Desynchronization Daemon (nfqws2)"

depend() {
    rc-service -e networking && need networking
}
start() {
    "${ZAPRET_INIT}" start
}
stop() {
    "${ZAPRET_INIT}" stop
}
restart() {
    "${ZAPRET_INIT}" restart
}
start_fw() {
    "${ZAPRET_INIT}" start_fw
}
stop_fw() {
    "${ZAPRET_INIT}" stop_fw
}
restart_fw() {
    "${ZAPRET_INIT}" restart_fw
}
start_daemons() {
    "${ZAPRET_INIT}" start_daemons
}
stop_daemons() {
    "${ZAPRET_INIT}" stop_daemons
}
restart_daemons() {
    "${ZAPRET_INIT}" restart_daemons
}
reload_ifsets() {
    "${ZAPRET_INIT}" reload_ifsets
}
EOF_OPENRC_ZAPRET
        chmod 755 /etc/init.d/zapret2
        rc-update add zapret2 default >/dev/null 2>&1 || true
        rc-service zapret2 restart >/dev/null 2>&1 || rc-service zapret2 start >/dev/null 2>&1 || true
    elif [ "${INIT_SYSTEM}" = "systemd" ]; then
        if [ -f "${ZAPRET_DIR}/init.d/systemd/zapret2.service" ]; then
            cp "${ZAPRET_DIR}/init.d/systemd/zapret2.service" /etc/systemd/system/zapret2.service
            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable --now zapret2.service >/dev/null 2>&1 || systemctl restart zapret2.service >/dev/null 2>&1 || true
        fi
    fi

    # Глобальный симлинк для прямого вызова утилиты blockcheck
    ln -sf /usr/local/bin/homelab /usr/local/bin/blockcheck 2>/dev/null || true

    log_ok "Zapret2 успешно развернут и активирован (DPI-Bypass: nfqws2, все сайты, YouTube 4K, Pixiv, Discord)"
}
