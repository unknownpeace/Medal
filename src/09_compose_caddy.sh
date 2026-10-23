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
    <li><span>🛡️ AdGuard Home</span><div class=\"links\"><a href=\"http://${ADGUARD_DOMAIN}\" target=\"_blank\" rel=\"noopener\">${ADGUARD_DOMAIN}</a><a class=\"alt\" href=\"http://${LOCAL_IP}:8083\" target=\"_blank\" rel=\"noopener\">IP :8083</a></div></li>
    <li><span>🚀 sing-box Gateway UI</span><div class=\"links\"><a href=\"http://${PROXY_DOMAIN}/#/?hostname=${LOCAL_IP}&port=9090&protocol=http&secret=${MIHOMO_SECRET_VAL}\" target=\"_blank\" rel=\"noopener\">${PROXY_DOMAIN} [Вход]</a><a class=\"alt\" href=\"http://${LOCAL_IP}:9090/ui/#/?hostname=${LOCAL_IP}&port=9090&protocol=http&secret=${MIHOMO_SECRET_VAL}\" target=\"_blank\" rel=\"noopener\">IP :9090</a></div></li>"
    fi
    if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🔑 Vaultwarden</span><div class=\"links\"><a href=\"https://${VAULT_DOMAIN}\" target=\"_blank\" rel=\"noopener\">${VAULT_DOMAIN} (HTTPS)</a><a class=\"alt\" href=\"http://${VAULT_DOMAIN}\" target=\"_blank\" rel=\"noopener\">HTTP</a><a class=\"alt\" href=\"http://${LOCAL_IP}:8000\" target=\"_blank\" rel=\"noopener\">IP :8000</a></div></li>"
    fi
    if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🐙 Forgejo Git Server</span><div class=\"links\"><a href=\"http://${GITEA_DOMAIN}\" target=\"_blank\" rel=\"noopener\">${GITEA_DOMAIN}</a><a class=\"alt\" href=\"http://${LOCAL_IP}:3000\" target=\"_blank\" rel=\"noopener\">IP :3000</a></div></li>"
    fi
    if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>📥 qBittorrent</span><div class=\"links\"><a href=\"http://${TORRENT_DOMAIN}\" target=\"_blank\" rel=\"noopener\">${TORRENT_DOMAIN}</a><a class=\"alt\" href=\"http://${LOCAL_IP}:8080\" target=\"_blank\" rel=\"noopener\">IP :8080</a></div></li>"
    fi
    if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>📥 MeTube (Загрузка видео)</span><div class=\"links\"><a href=\"http://${METUBE_DOMAIN}\" target=\"_blank\" rel=\"noopener\">${METUBE_DOMAIN}</a><a class=\"alt\" href=\"http://${LOCAL_IP}:8081\" target=\"_blank\" rel=\"noopener\">IP :8081</a></div></li>"
    fi
    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>🎵 Navidrome Music</span><div class=\"links\"><a href=\"http://${MUSIC_DOMAIN}\" target=\"_blank\" rel=\"noopener\">${MUSIC_DOMAIN}</a><a class=\"alt\" href=\"http://${LOCAL_IP}:4533\" target=\"_blank\" rel=\"noopener\">IP :4533</a></div></li>"
    fi
    if ! is_native; then
        IP_PORTAL_ITEMS="${IP_PORTAL_ITEMS}
    <li><span>📋 Dozzle Web Logs</span><div class=\"links\"><a href=\"http://${LOGS_DOMAIN}\" target=\"_blank\" rel=\"noopener\">${LOGS_DOMAIN}</a></div></li>"
    fi

    local VAULT_UPSTREAM="127.0.0.1:8000"
    local GITEA_UPSTREAM="127.0.0.1:3000"
    local QBIT_UPSTREAM="127.0.0.1:8080"
    local METUBE_UPSTREAM="127.0.0.1:8081"
    local NAVI_UPSTREAM="127.0.0.1:4533"
    local AGH_UPSTREAM="127.0.0.1:8083"
    local PROXY_API_UPSTREAM="127.0.0.1:9090"
    local CADDY_CERT_DIR="/var/lib/caddy/.local/share/caddy/pki/authorities/local"
    local CADDY_UI_ROOT="${APP_DIR}/mihomo/ui"

    if [ "${DISTRO_FAMILY}" != "alpine" ]; then
        VAULT_UPSTREAM="vaultwarden:80"
        GITEA_UPSTREAM="gitea:3000"
        QBIT_UPSTREAM="qbittorrent:8080"
        METUBE_UPSTREAM="metube:8081"
        NAVI_UPSTREAM="navidrome:4533"
        AGH_UPSTREAM="host.docker.internal:8083"
        PROXY_API_UPSTREAM="host.docker.internal:9090"
        CADDY_CERT_DIR="/data/caddy/pki/authorities/local"
        CADDY_UI_ROOT="/srv/mihomo-ui"
    fi

    cat <<EOF_CADDY > "${APP_DIR}/caddy/Caddyfile"
{
    admin off
    auto_https disable_redirects
}

(security_headers) {
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "0"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"
    }
}

(hsts_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }
}

http://${LOCAL_IP}, http://homelab.lan, http://homelab.local {
    @cert path /caddy-root.crt /root.crt
    handle @cert {
        root * ${CADDY_CERT_DIR}
        rewrite * /root.crt
        file_server
    }

    handle {
        reverse_proxy 127.0.0.1:8082
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
    import hsts_headers
    encode zstd gzip
EOF_CADDY

        if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @vault host ${VAULT_DOMAIN}
    handle @vault {
        reverse_proxy ${VAULT_UPSTREAM}
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @gitea host ${GITEA_DOMAIN}
    handle @gitea {
        reverse_proxy ${GITEA_UPSTREAM}
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @torrent host ${TORRENT_DOMAIN}
    handle @torrent {
        reverse_proxy ${QBIT_UPSTREAM}
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @metube host ${METUBE_DOMAIN} tube.${BASE_DOMAIN}
    handle @metube {
        reverse_proxy ${METUBE_UPSTREAM}
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @music host ${MUSIC_DOMAIN}
    handle @music {
        reverse_proxy ${NAVI_UPSTREAM}
    }
EOF_CADDY
        fi

        if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
    @adguard host ${ADGUARD_DOMAIN}
    handle @adguard {
        reverse_proxy ${AGH_UPSTREAM}
    }

    @proxy host ${PROXY_DOMAIN}
    handle @proxy {
        @api path /api*
        handle @api {
            uri strip_prefix /api
            reverse_proxy ${PROXY_API_UPSTREAM}
        }

        @clash_api path /version* /proxies* /rules* /connections* /configs* /logs* /traffic* /memory* /providers* /dns* /group*
        handle @clash_api {
            reverse_proxy ${PROXY_API_UPSTREAM}
        }

        handle {
            root * ${CADDY_UI_ROOT}
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
        reverse_proxy 127.0.0.1:8083
    }
EOF_CADDY
        echo "}" >> "${APP_DIR}/caddy/Caddyfile"

    else
        if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
http://${VAULT_DOMAIN}, https://${VAULT_DOMAIN}, http://vault.local, https://vault.local {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy ${VAULT_UPSTREAM}
}
EOF_CADDY
        fi

        if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
http://${GITEA_DOMAIN}, https://${GITEA_DOMAIN}, http://git.local, https://git.local {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy ${GITEA_UPSTREAM}
}
EOF_CADDY
        fi

        if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
http://${TORRENT_DOMAIN}, https://${TORRENT_DOMAIN}, http://torrent.local, https://torrent.local {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy ${QBIT_UPSTREAM}
}
EOF_CADDY
        fi

        if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
http://${METUBE_DOMAIN}, http://tube.lan, http://metube.local, http://tube.local, https://${METUBE_DOMAIN}, https://tube.lan, https://metube.local, https://tube.local {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy ${METUBE_UPSTREAM}
}
EOF_CADDY
        fi

        if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
http://${MUSIC_DOMAIN}, https://${MUSIC_DOMAIN}, http://music.local, https://music.local {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy ${NAVI_UPSTREAM}
}
EOF_CADDY
        fi

        if [[ "${ENABLE_GATEWAY}" =~ ^[Yy]$ ]]; then
            cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
http://${ADGUARD_DOMAIN}, https://${ADGUARD_DOMAIN}, http://adguard.local, https://adguard.local {
    tls internal
    import security_headers
    encode zstd gzip
    reverse_proxy ${AGH_UPSTREAM}
}

http://${PROXY_DOMAIN}, https://${PROXY_DOMAIN}, http://proxy.local, https://proxy.local {
    tls internal
    import security_headers
    encode zstd gzip

    @api path /api*
    handle @api {
        uri strip_prefix /api
        reverse_proxy ${PROXY_API_UPSTREAM}
    }

    @clash_api path /version* /proxies* /rules* /connections* /configs* /logs* /traffic* /memory* /providers* /dns* /group*
    handle @clash_api {
        reverse_proxy ${PROXY_API_UPSTREAM}
    }

    handle {
        root * ${CADDY_UI_ROOT}
        file_server
        try_files {path} {path}/ /index.html
    }
}
EOF_CADDY
        fi

        cat <<EOF_CADDY >> "${APP_DIR}/caddy/Caddyfile"
http://${LOGS_DOMAIN}, https://${LOGS_DOMAIN}, http://logs.local, https://logs.local {
    tls internal
    import security_headers
    encode zstd gzip
    basic_auth {
        ${ADMIN_USER} ${AGH_HASH_CADDY}
    }
    reverse_proxy ${AGH_UPSTREAM}
}
EOF_CADDY
    fi

    if [ "${DISTRO_FAMILY}" = "alpine" ] || is_native; then
        log_info "Конфигурация нативных служб Alpine Linux (Zero-Docker OpenRC)..."

        # 1. Caddy
        mkdir -p /etc/caddy /var/lib/caddy
        cp -f "${APP_DIR}/caddy/Caddyfile" /etc/caddy/Caddyfile 2>/dev/null || true
        touch /var/log/caddy.log && chown caddy:caddy /var/log/caddy.log 2>/dev/null || true
        setcap cap_net_bind_service=+ep /usr/sbin/caddy 2>/dev/null || true
        chown -R caddy:caddy /etc/caddy /var/lib/caddy 2>/dev/null || true
        cat << 'EOF_CADDY_CONF' > /etc/conf.d/caddy
output_log="/var/log/caddy.log"
error_log="/var/log/caddy.log"
EOF_CADDY_CONF
        cat << 'EOF_AGH_CONF' >> /etc/conf.d/adguardhome
output_log="/var/log/adguardhome.log"
error_log="/var/log/adguardhome.log"
EOF_AGH_CONF

        # 2. Samba & WSDD
        if [[ "${ENABLE_SAMBA}" =~ ^[Yy]$ ]]; then
            mkdir -p /etc/samba
            cat << EOF_SMB > /etc/samba/smb.conf
[global]
    workgroup = WORKGROUP
    server string = Homelab Appliance Storage
    security = user
    map to guest = Bad User
    dns proxy = no
    log file = /var/log/samba/%m.log
    max log size = 50

[${SHARE_NAME}]
    path = ${SAVE_DIR}
    valid users = ${ADMIN_USER_SAFE}
    read only = no
    browsable = yes
    create mask = 0664
    directory mask = 0775

[music]
    path = ${SAVE_DIR}/music
    valid users = ${ADMIN_USER_SAFE}
    read only = no
    browsable = yes
    create mask = 0664
    directory mask = 0775
EOF_SMB
            id -u "${ADMIN_USER_SAFE}" >/dev/null 2>&1 || adduser -D -s /sbin/nologin "${ADMIN_USER_SAFE}" 2>/dev/null || true
            (echo "${SAMBA_PASS}"; echo "${SAMBA_PASS}") | smbpasswd -a -s "${ADMIN_USER_SAFE}" 2>/dev/null || true
            smbpasswd -e "${ADMIN_USER_SAFE}" 2>/dev/null || true
        fi

        # 3. Vaultwarden
        if [[ "${ENABLE_VAULT}" =~ ^[Yy]$ ]]; then
            mkdir -p /var/lib/vaultwarden
            cat << EOF_VW > /etc/conf.d/vaultwarden
export ROCKET_ADDRESS=0.0.0.0
export ROCKET_PORT=8000
export DATA_FOLDER=/var/lib/vaultwarden
export WEB_VAULT_FOLDER=/usr/share/webapps/vaultwarden-web
export ADMIN_TOKEN='${VAULT_ADMIN_HASH}'
export SIGNUPS_ALLOWED=true
output_log="/var/log/vaultwarden.log"
error_log="/var/log/vaultwarden.log"
EOF_VW
            ln -sf /usr/share/webapps/vaultwarden-web /var/lib/vaultwarden/web-vault 2>/dev/null || true
            chown -R vaultwarden:vaultwarden /var/lib/vaultwarden "${VAULT_DATA_DIR}" /usr/share/webapps/vaultwarden-web 2>/dev/null || true
        fi

        # 4. Forgejo (Git-сервер)
        if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
            mkdir -p /var/lib/forgejo/data/forgejo-repositories /etc/forgejo /var/log/forgejo
            cat << EOF_FORGEJO > /etc/forgejo/app.ini
APP_NAME = Homelab Git Server
RUN_USER = forgejo
RUN_MODE = prod

[server]
PROTOCOL = http
DOMAIN = ${GITEA_DOMAIN}
ROOT_URL = https://${GITEA_DOMAIN}/
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
DISABLE_SSH = false
SSH_PORT = 22

[database]
DB_TYPE = sqlite3
PATH = /var/lib/forgejo/data/forgejo.db

[security]
INSTALL_LOCK = true
SECRET_KEY = 4f9e1b2c3d4e5f6a7b8c9d0e1f2a3b4c
REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1
EOF_FORGEJO
            chown -R forgejo:www-data /var/lib/forgejo /var/log/forgejo /etc/forgejo 2>/dev/null || true
        fi

        # 5. Navidrome (Hi-Fi Music)
        if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
            mkdir -p /var/lib/navidrome "${SAVE_DIR}/music" /etc/navidrome
            cat << EOF_NAVI > /etc/navidrome/navidrome.toml
Address = "0.0.0.0"
Port = 4533
MusicFolder = "${SAVE_DIR}/music"
DataFolder = "/var/lib/navidrome"
LogLevel = "info"
ScanSchedule = "1m"
EOF_NAVI
            ln -sf /etc/navidrome/navidrome.toml /etc/navidrome.toml 2>/dev/null || true
            cat << 'EOF_NAVI_CONFD' > /etc/conf.d/navidrome
navidrome_configfile=/etc/navidrome/navidrome.toml
error_log=/var/log/navidrome.log
EOF_NAVI_CONFD
            chown -R navidrome:navidrome /var/lib/navidrome "${SAVE_DIR}/music" /etc/navidrome 2>/dev/null || true
        fi

        # 6. qBittorrent
        if [[ "${ENABLE_QBIT}" =~ ^[Yy]$ ]]; then
            mkdir -p /var/lib/qbittorrent/.config/qBittorrent
            cp -f "${APP_DIR}/qbittorrent/config/qBittorrent/qBittorrent.conf" /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf 2>/dev/null || true
            sed -i "s|/downloads/temp/|${SAVE_DIR}/temp/|g; s|/downloads/|${SAVE_DIR}/downloads/|g; s|/vuetorrent|${APP_DIR}/qbittorrent/vuetorrent|g" /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf 2>/dev/null || true
            chown -R qbittorrent:qbittorrent /var/lib/qbittorrent 2>/dev/null || true
            cat << 'EOF_QBIT_CONF' > /etc/conf.d/qbittorrent-nox
pidfile="/run/qbittorrent-nox.pid"
EOF_QBIT_CONF
        fi

        # 7. Native yt-dlp Web UI Downloader
        if [[ "${ENABLE_METUBE}" =~ ^[Yy]$ ]]; then
            cat << 'EOF_YTDL_PY' > "${APP_DIR}/scripts/ytdlp_web.py"
#!/usr/bin/env python3
import sys, os, subprocess, json, threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs

SAVE_DIR = os.environ.get("SAVED_SAVE_DIR", "/opt/homelab/save")
DOWNLOADS_DIR = os.path.join(SAVE_DIR, "downloads")
MUSIC_DIR = os.path.join(SAVE_DIR, "music")
os.makedirs(DOWNLOADS_DIR, exist_ok=True)
os.makedirs(MUSIC_DIR, exist_ok=True)

HTML_PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Homelab Downloader</title>
<style>
:root { --bg: #0b0f19; --card: #111827; --border: #1f2937; --accent: #38bdf8; --green: #10b981; --text: #f3f4f6; }
body { background: var(--bg); color: var(--text); font-family: system-ui, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; }
.card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 32px; max-width: 520px; width: 100%; box-shadow: 0 20px 40px rgba(0,0,0,0.6); }
h1 { color: var(--accent); font-size: 22px; margin: 0 0 16px; display: flex; align-items: center; gap: 8px; }
input[type="text"] { width: 100%; box-sizing: border-box; padding: 12px 14px; background: #1e293b; border: 1px solid #334155; border-radius: 8px; color: #fff; font-size: 14px; margin-bottom: 14px; }
select { width: 100%; box-sizing: border-box; padding: 12px 14px; background: #1e293b; border: 1px solid #334155; border-radius: 8px; color: #fff; font-size: 14px; margin-bottom: 18px; }
button { width: 100%; padding: 12px; background: #0284c7; color: #fff; font-weight: bold; border: none; border-radius: 8px; cursor: pointer; font-size: 14px; transition: background 0.2s; }
button:hover { background: #0369a1; }
.msg { margin-top: 14px; padding: 10px; border-radius: 6px; font-size: 13px; display: none; }
.msg.ok { background: rgba(16, 185, 129, 0.15); color: #34d399; border: 1px solid #10b981; display: block; }
.msg.err { background: rgba(239, 68, 68, 0.15); color: #f87171; border: 1px solid #ef4444; display: block; }
</style>
</head>
<body>
<div class="card">
  <h1>🎬 Homelab Downloader</h1>
  <p style="color:#94a3b8; font-size:13px; margin-bottom:16px;">Вставьте ссылку на видео или музыку (YouTube, VK, RuTube и др.):</p>
  <form method="POST" action="/download">
    <input type="text" name="url" placeholder="https://..." required autofocus>
    <select name="format">
      <option value="video">Видео (MP4 Лучшее качество)</option>
      <option value="audio">Аудио (MP3 Музыка)</option>
    </select>
    <button type="submit">⬇ Скачать в хранилище</button>
  </form>
  <div id="status" class="msg"></div>
</div>
</body>
</html>"""

def run_download(url, fmt):
    dest = MUSIC_DIR if fmt == "audio" else DOWNLOADS_DIR
    cmd = ["yt-dlp", "--no-warnings", "-P", dest]
    if fmt == "audio":
        cmd += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
    else:
        cmd += ["-f", "bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
    cmd.append(url)
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

class DownloaderHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(HTML_PAGE.encode("utf-8"))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="ignore")
        data = parse_qs(body)
        url = data.get("url", [""])[0].strip()
        fmt = data.get("format", ["video"])[0].strip()
        if url:
            threading.Thread(target=run_download, args=(url, fmt), daemon=True).start()
            resp = HTML_PAGE.replace('<div id="status" class="msg"></div>', '<div id="status" class="msg ok">✔ Загрузка запущена в фоновом режиме! Файл будет сохранен в хранилище.</div>')
        else:
            resp = HTML_PAGE.replace('<div id="status" class="msg"></div>', '<div id="status" class="msg err">✖ Введите корректную ссылку.</div>')
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(resp.encode("utf-8"))

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8081), DownloaderHandler)
    server.serve_forever()
EOF_YTDL_PY
            chmod 755 "${APP_DIR}/scripts/ytdlp_web.py"

            cat << EOF_YTDL_INIT > /etc/init.d/ytdlp-web
#!/sbin/openrc-run
name="ytdlp-web"
description="yt-dlp Web Media Downloader"
supervisor="supervise-daemon"
command="/usr/bin/python3"
command_args="${APP_DIR}/scripts/ytdlp_web.py"
output_log="/var/log/ytdlp-web.log"
error_log="/var/log/ytdlp-web.log"
respawn_delay=2
respawn_max=5

depend() {
    need net
}
EOF_YTDL_INIT
            chmod 755 /etc/init.d/ytdlp-web
        fi

        # 8. Web Management Portal & Mode Switcher Daemon (homelab-portal on 127.0.0.1:8082)
        cat << 'EOF_PORTAL_PY' > "${APP_DIR}/scripts/portal_web.py"
#!/usr/bin/env python3
import os, sys, subprocess, json, re, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

ENV_FILE = "/opt/homelab/.env"

def load_env():
    env = {}
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        env[k.strip()] = v.strip().strip("'\"")
        except Exception:
            pass
    return env

class PortalHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        env = load_env()
        parsed_url = urlparse(self.path)
        qs = parse_qs(parsed_url.query)
        switched = qs.get("switched", [""])[0]

        local_ip = env.get("SAVED_LOCAL_IP", env.get("LOCAL_IP", "127.0.0.1"))
        router_mode = env.get("SAVED_ROUTER_MODE", env.get("ROUTER_MODE", "1"))
        secret = env.get("SAVED_MIHOMO_SECRET", env.get("MIHOMO_SECRET", ""))
        admin_user = env.get("SAVED_ADMIN_USER", "admin")
        share_name = env.get("SAVED_SHARE_NAME", "storage")

        if router_mode == "2":
            mode_badge = '<span class="badge badge-router">⚡ РЕЖИМ: ДОМАШНИЙ РОУТЕР (WAN + LAN)</span>'
            mode_desc = f'<b>Сервер заменяет домашний роутер.</b> DHCP-сервер в AdGuard Home <b>ВКЛЮЧЕН</b> (пул .50-.250). WAN: <code>{env.get("SAVED_WAN_IFACE","eth0")}</code>, LAN: <code>{env.get("SAVED_LAN_IFACE","wlan0")}</code>. Keenetic (192.168.1.5) защищен.'
            switch_btn = '<form method="POST" action="/api/mode"><input type="hidden" name="mode" value="1"><button type="submit" class="btn-mode btn-mode-gw">🔄 Переключить в режим &quot;Прозрачный шлюз&quot; (DHCP в Keenetic)</button></form>'
        else:
            mode_badge = '<span class="badge badge-gw">⚡ РЕЖИМ: ПРОЗРАЧНЫЙ ШЛЮЗ (GATEWAY)</span>'
            mode_desc = f'<b>Сервер работает в паре с основным роутером.</b> DHCP-сервер в AdGuard Home <b>ОТКЛЮЧЕН</b> (работает DHCP Keenetic на 192.168.1.5). LAN адаптер: <code>{env.get("SAVED_PHYS_IFACE","eth0")}</code>.'
            switch_btn = '<form method="POST" action="/api/mode"><input type="hidden" name="mode" value="2"><button type="submit" class="btn-mode btn-mode-router">🔄 Переключить в режим &quot;Домашний роутер&quot; (WAN + LAN)</button></form>'

        flash_msg = ""
        if switched:
            flash_msg = f'<div class="flash">✔ Режим сети успешно изменен на {"Домашний роутер" if switched == "2" else "Прозрачный шлюз"}! DHCP и правила фаервола синхронизированы.</div>'

        html = f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Homelab Appliance &amp; Gateway</title>
<style>
body {{ background: #080d1a; color: #f8fafc; font-family: system-ui, -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }}
.card {{ background: #0f172a; border: 1px solid #1e293b; border-radius: 16px; padding: 28px; max-width: 620px; width: 100%; box-shadow: 0 20px 45px rgba(0,0,0,0.7); }}
h1 {{ color: #38bdf8; font-size: 24px; margin: 0 0 12px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; }}
.badge {{ font-size: 11px; padding: 4px 10px; border-radius: 6px; font-weight: bold; letter-spacing: 0.5px; }}
.badge-online {{ background: #065f46; color: #6ee7b7; }}
.badge-gw {{ background: #1e3a8a; color: #93c5fd; }}
.badge-router {{ background: #854d0e; color: #fde047; }}
.mode-box {{ background: #131e36; border: 1px solid #1e293b; border-radius: 10px; padding: 14px 16px; margin: 16px 0; }}
.mode-box p {{ color: #cbd5e1; font-size: 13px; line-height: 1.5; margin: 8px 0 12px; }}
.btn-mode {{ width: 100%; padding: 10px 14px; border: none; border-radius: 8px; font-weight: 600; font-size: 13px; cursor: pointer; transition: background 0.2s; }}
.btn-mode-gw {{ background: #0284c7; color: #fff; }}
.btn-mode-gw:hover {{ background: #0369a1; }}
.btn-mode-router {{ background: #d97706; color: #fff; }}
.btn-mode-router:hover {{ background: #b45309; }}
.flash {{ background: rgba(16, 185, 129, 0.15); border: 1px solid #10b981; color: #34d399; padding: 10px 14px; border-radius: 8px; font-size: 13px; margin-bottom: 16px; }}
.list {{ list-style: none; padding: 0; margin: 16px 0; }}
.list li {{ margin-bottom: 8px; display: flex; justify-content: space-between; align-items: center; padding: 10px 14px; background: #131e36; border-radius: 8px; border: 1px solid #1e293b; font-size: 14px; gap: 8px; }}
.links {{ display: flex; gap: 6px; flex-wrap: wrap; }}
.list a {{ color: #38bdf8; text-decoration: none; font-weight: 600; font-family: monospace; font-size: 13px; background: rgba(56, 189, 248, 0.1); padding: 4px 8px; border-radius: 4px; transition: all 0.2s; white-space: nowrap; }}
.list a:hover {{ background: rgba(56, 189, 248, 0.25); text-decoration: underline; }}
.list a.alt {{ background: rgba(148, 163, 184, 0.12); color: #94a3b8; }}
.list a.alt:hover {{ background: rgba(148, 163, 184, 0.25); color: #f8fafc; text-decoration: underline; }}
.btn-cert {{ display: block; text-align: center; background: #0284c7; color: #fff; text-decoration: none; font-weight: 600; font-size: 13px; padding: 10px 16px; border-radius: 8px; margin: 14px 0 10px; transition: background 0.2s; }}
.btn-cert:hover {{ background: #0369a1; }}
.tip {{ background: rgba(56, 189, 248, 0.08); border-left: 3px solid #38bdf8; padding: 12px; font-size: 13px; color: #cbd5e1; border-radius: 4px; margin-top: 14px; line-height: 1.5; }}
code {{ background: #1e293b; color: #38bdf8; padding: 2px 6px; border-radius: 4px; font-size: 12px; }}
</style>
</head>
<body>
<div class="card">
  <h1><span>⚡ Homelab Appliance</span> <span class="badge badge-online">ONLINE</span></h1>
  {flash_msg}
  <div class="mode-box">
    <div>{mode_badge}</div>
    <p>{mode_desc}</p>
    {switch_btn}
  </div>
  <ul class="list">
    <li><span>🛡️ AdGuard Home</span><div class="links"><a href="http://adguard.lan" target="_blank" rel="noopener">adguard.lan</a><a class="alt" href="http://adguard.local" target="_blank" rel="noopener">.local</a><a class="alt" href="http://{local_ip}:8083" target="_blank" rel="noopener">IP :8083</a></div></li>
    <li><span>🚀 sing-box UI</span><div class="links"><a href="http://proxy.lan/#/?hostname={local_ip}&port=9090&protocol=http&secret={secret}" target="_blank" rel="noopener">proxy.lan [Вход]</a><a class="alt" href="http://{local_ip}:9090/ui/#/?hostname={local_ip}&port=9090&protocol=http&secret={secret}" target="_blank" rel="noopener">IP :9090</a></div></li>
    <li><span>🔑 Vaultwarden</span><div class="links"><a href="http://vault.lan" target="_blank" rel="noopener">vault.lan</a><a class="alt" href="https://vault.lan" target="_blank" rel="noopener">HTTPS</a><a class="alt" href="http://{local_ip}:8000" target="_blank" rel="noopener">IP :8000</a></div></li>
    <li><span>🐙 Forgejo Git Server</span><div class="links"><a href="http://git.lan" target="_blank" rel="noopener">git.lan</a><a class="alt" href="http://git.local" target="_blank" rel="noopener">.local</a><a class="alt" href="http://{local_ip}:3000" target="_blank" rel="noopener">IP :3000</a></div></li>
    <li><span>📥 qBittorrent</span><div class="links"><a href="http://torrent.lan" target="_blank" rel="noopener">torrent.lan</a><a class="alt" href="http://torrent.local" target="_blank" rel="noopener">.local</a><a class="alt" href="http://{local_ip}:8080" target="_blank" rel="noopener">IP :8080</a></div></li>
    <li><span>🎬 MeTube (Загрузка видео)</span><div class="links"><a href="http://metube.lan" target="_blank" rel="noopener">metube.lan</a><a class="alt" href="http://metube.local" target="_blank" rel="noopener">.local</a><a class="alt" href="http://{local_ip}:8081" target="_blank" rel="noopener">IP :8081</a></div></li>
    <li><span>🎵 Navidrome Music</span><div class="links"><a href="http://music.lan" target="_blank" rel="noopener">music.lan</a><a class="alt" href="http://music.local" target="_blank" rel="noopener">.local</a><a class="alt" href="http://{local_ip}:4533" target="_blank" rel="noopener">IP :4533</a></div></li>
    <li><span>📂 Samba Хранилище</span><div class="links"><a class="alt" href="file:///{local_ip}/{share_name}">\\\\{local_ip}\\{share_name}</a><a class="alt" href="file:///{local_ip}/music">\\\\{local_ip}\\music</a></div></li>
  </ul>
  <a class="btn-cert" href="/caddy-root.crt" download>📥 Скачать Root CA Сертификат (caddy-root.crt)</a>
  <div class="tip">
    💡 <b>Настройка роутера Keenetic:</b> В меню роутера укажите <code>DNS: {local_ip}</code> и <code>Шлюз: {local_ip}</code>, чтобы все устройства домашней сети автоматически переходили по доменам <code>*.lan</code> и получили чистый интернет без рекламы и блокировок.<br><br>
    ⚡ <b>Команда Windows PowerShell для мгновенного доверия SSL:</b><br>
    <code>irm http://{local_ip}/caddy-root.crt -OutFile $env:TEMP\\ca.crt; certutil -user -addstore -f Root $env:TEMP\\ca.crt</code>
  </div>
</div>
</body>
</html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode("utf-8"))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="ignore")
        data = parse_qs(body)
        mode = data.get("mode", ["1"])[0].strip()
        if mode in ("1", "2"):
            subprocess.run(["/usr/local/bin/homelab", "mode", mode], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.send_response(303)
            self.send_header("Location", f"/?switched={mode}")
            self.end_headers()
        else:
            self.send_response(400)
            self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8082), PortalHandler)
    server.serve_forever()
EOF_PORTAL_PY
        chmod 755 "${APP_DIR}/scripts/portal_web.py"

        cat << EOF_PORTAL_INIT > /etc/init.d/homelab-portal
#!/sbin/openrc-run
name="homelab-portal"
description="Homelab Web Management Portal"
supervisor="supervise-daemon"
command="/usr/bin/python3"
command_args="${APP_DIR}/scripts/portal_web.py"
output_log="/var/log/homelab-portal.log"
error_log="/var/log/homelab-portal.log"
respawn_delay=2
respawn_max=5

depend() {
    need net
    before caddy
    after network
}
EOF_PORTAL_INIT
        chmod 755 /etc/init.d/homelab-portal

        # 9. mDNS Zeroconf Avahi Hosts
        if [ -d /etc/avahi ]; then
            cat << EOF_AVAHI > /etc/avahi/hosts
${LOCAL_IP} homelab.local
${LOCAL_IP} adguard.local
${LOCAL_IP} proxy.local
${LOCAL_IP} vault.local
${LOCAL_IP} git.local
${LOCAL_IP} torrent.local
${LOCAL_IP} metube.local
${LOCAL_IP} tube.local
${LOCAL_IP} music.local
${LOCAL_IP} logs.local
EOF_AVAHI
            rc-update add dbus default >/dev/null 2>&1 || true
            rc-service dbus status >/dev/null 2>&1 || rc-service dbus start >/dev/null 2>&1 || true
            rc-update add avahi-daemon default >/dev/null 2>&1 || true
            rc-service avahi-daemon status >/dev/null 2>&1 || rc-service avahi-daemon restart >/dev/null 2>&1 || true
        fi

        # 10. Master OpenRC meta-service
        cat << 'EOF_HOMELAB_RC' > /etc/init.d/homelab
#!/sbin/openrc-run
description="Homelab Native Bare-Metal Appliance"

depend() {
    need net
    after network
}

start() {
    ebegin "Starting Homelab Appliance Services"
    for svc in sing-box adguardhome homelab-portal caddy vaultwarden forgejo samba wsdd qbittorrent-nox navidrome ytdlp-web avahi-daemon; do
        if [ -f "/etc/init.d/$svc" ]; then
            rc-service "$svc" status >/dev/null 2>&1 || rc-service "$svc" start >/dev/null 2>&1 || true
        fi
    done
    [ -x /usr/local/bin/gateway-watchdog.sh ] && /usr/local/bin/gateway-watchdog.sh 2>/dev/null || true
    eend 0
}

stop() {
    ebegin "Stopping Homelab Appliance Services"
    for svc in ytdlp-web navidrome qbittorrent-nox wsdd samba forgejo vaultwarden caddy homelab-portal adguardhome sing-box avahi-daemon; do
        if [ -f "/etc/init.d/$svc" ]; then
            rc-service "$svc" stop >/dev/null 2>&1 || true
        fi
    done
    eend 0
}

restart() {
    ebegin "Restarting Homelab Appliance Services"
    for svc in sing-box adguardhome homelab-portal caddy vaultwarden forgejo samba wsdd qbittorrent-nox navidrome ytdlp-web avahi-daemon; do
        if [ -f "/etc/init.d/$svc" ]; then
            rc-service "$svc" restart >/dev/null 2>&1 || true
        fi
    done
    [ -x /usr/local/bin/gateway-watchdog.sh ] && /usr/local/bin/gateway-watchdog.sh 2>/dev/null || true
    eend 0
}
EOF_HOMELAB_RC
        chmod 755 /etc/init.d/homelab
        rc-update add homelab default >/dev/null 2>&1 || true
        rc-update add homelab-portal default >/dev/null 2>&1 || true

        log_ok "Нативные конфигурации OpenRC и Caddyfile успешно подготовлены"
        return 0
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
      timeout: 10s
      retries: 5
      start_period: 30s
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
      timeout: 10s
      retries: 5
      start_period: 90s
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
      timeout: 10s
      retries: 5
      start_period: 45s
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
      - "YTDL_NIGHTLY_UPDATE_TIME=04:30"
      - "DEFAULT_THEME=auto"
    volumes:
      - ${SAVE_DIR}/downloads:/downloads
      - ${SAVE_DIR}/music:/music
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:8081/ 2>/dev/null || curl -fs http://localhost:8081/ >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
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
      timeout: 10s
      retries: 5
      start_period: 60s
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
      timeout: 10s
      retries: 5
      start_period: 30s
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
      - "AUTOHEAL_INTERVAL=30"
      - "AUTOHEAL_START_PERIOD=60"
      - "AUTOHEAL_DEFAULT_STOP_TIMEOUT=15"
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
      timeout: 10s
      retries: 5
      start_period: 30s
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
    local retries=0
    while [ ! -S /var/run/docker.sock ] && [ \$retries -lt 15 ]; do
        sleep 1
        retries=\$((retries + 1))
    done
    cd "${APP_DIR}" && /usr/local/bin/dc up -d
    local ec=\$?
    [ -x /usr/local/bin/gateway-watchdog.sh ] && /usr/local/bin/gateway-watchdog.sh 2>/dev/null || true
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
