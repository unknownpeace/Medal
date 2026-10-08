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

        # Полная очистка и удаление любых следов Zapret (службы, процессы, таблицы nftables)
        if [ "${INIT_SYSTEM}" = "openrc" ]; then
            rc-service zapret2 stop >/dev/null 2>&1 || true
            rc-update del zapret2 default >/dev/null 2>&1 || true
            rm -f /etc/init.d/zapret2
        elif [ "${INIT_SYSTEM}" = "systemd" ]; then
            systemctl disable --now zapret2.service >/dev/null 2>&1 || true
            rm -f /etc/systemd/system/zapret2.service
            systemctl daemon-reload >/dev/null 2>&1 || true
        fi
        pkill -9 nfqws2 >/dev/null 2>&1 || true
        rm -rf /opt/zapret2 /usr/local/bin/blockcheck /etc/sysctl.d/99-zapret.conf /etc/modules-load.d/zapret.conf
        if command -v nft >/dev/null 2>&1; then
            nft delete table inet zapret2 >/dev/null 2>&1 || true
        fi

        # Полная очистка и удаление любых следов Telegram-бота (служба, процессы, скрипт, конфиг)
        if [ "${INIT_SYSTEM}" = "openrc" ]; then
            rc-service homelab-bot stop >/dev/null 2>&1 || true
            rc-update del homelab-bot default >/dev/null 2>&1 || true
            rm -f /etc/init.d/homelab-bot
        elif [ "${INIT_SYSTEM}" = "systemd" ]; then
            systemctl disable --now homelab-bot.service >/dev/null 2>&1 || true
            rm -f /etc/systemd/system/homelab-bot.service
            systemctl daemon-reload >/dev/null 2>&1 || true
        fi
        pkill -9 -f "homelab-bot.py" >/dev/null 2>&1 || true
        rm -rf "${APP_DIR}/scripts/homelab-bot.py" "${APP_DIR}/configs/bot" /var/log/homelab-bot.* /run/homelab-bot.pid /usr/local/bin/yt-dlp

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
        cat << 'EOF_WATCHDOG' > /usr/local/bin/gateway-watchdog.sh
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
        chmod 750 /usr/local/bin/gateway-watchdog.sh

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
    for DOMAIN in "${VAULT_DOMAIN}" "${GITEA_DOMAIN}" "${ADGUARD_DOMAIN}" "${TORRENT_DOMAIN}" "${METUBE_DOMAIN}" "tube.lan" "${MUSIC_DOMAIN}" "${PROXY_DOMAIN}" "${LOGS_DOMAIN}"; do
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
    cat << 'EOF_NOTIFY' > /usr/local/bin/homelab-notify
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
    chmod 755 /usr/local/bin/homelab-notify

    log_ok "Сетевой стек, сторож маршрутизации и служба оповещений настроены"
}
