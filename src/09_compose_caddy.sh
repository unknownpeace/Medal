#!/usr/bin/env bash
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
    if [[ "${ENABLE_TG_BOT}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🤖 Telegram Control Bot</span><span style=\"color:#a0aec0;font-size:0.9em\">Управление комплексом, OTA-обновления, алерты</span></li>"
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
      - "PUID=${USER_UID}"
      - "PGID=${USER_GID}"
      - "UID=${USER_UID}"
      - "GID=${USER_GID}"
      - "ALLOW_PRIVATE_ADDRESSES=true"
      - "DOWNLOAD_DIR=/downloads"
      - "STATE_DIR=/downloads/.metube"
      - "TEMP_DIR=/downloads/tmp"
      - 'YTDL_OPTIONS={"extractor_args":{"youtube":{"player_client":["android","web"]}}}'
    volumes:
      - ${SAVE_DIR}/downloads:/downloads
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
    user: "${USER_UID}:${USER_GID}"
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
      - "WATCHTOWER_POLL_INTERVAL=86400"
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
    eend $?
}
restart() {
    ebegin "Restarting Homelab Docker Compose Stack"
    cd "${APP_DIR}" && /usr/local/bin/dc restart
    eend $?
}
EOF_HOMELAB_RC
        chmod 755 /etc/init.d/homelab
        rc-update add homelab default >/dev/null 2>&1 || true
    fi

    log_ok "Caddyfile, docker-compose.yml и служба автозапуска успешно сформированы"
}
