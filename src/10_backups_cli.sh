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

    run_spin "Загрузка Docker-образов стека" bash -c '
        if dc config --images >/dev/null 2>&1; then
            for img in $(dc config --images 2>/dev/null); do
                docker pull "${img}" >/dev/null 2>&1 || true
            done
        else
            dc pull -q 2>/dev/null || dc pull
        fi
    '
    run_spin "Запуск контейнеров стека (Docker Compose)" bash -c "dc up -d --quiet-pull 2>/dev/null || dc up -d"

    if [[ "${ENABLE_GITEA}" =~ ^[Yy]$ ]]; then
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

    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        log_info "Автоматическая инициализация администратора Navidrome (${ADMIN_USER})..."
        local NAVIDROME_READY=0
        for i in {1..30}; do
            if docker inspect -f '{{.State.Status}}' navidrome 2>/dev/null | grep -q "running"; then
                local RES_CREATE
                RES_CREATE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:4533/api/user" \
                    -H "Content-Type: application/json" \
                    -d "{\"userName\":\"${ADMIN_USER}\",\"username\":\"${ADMIN_USER}\",\"name\":\"${ADMIN_USER}\",\"password\":\"${MASTER_PASS}\",\"isAdmin\":true}" 2>/dev/null || echo "000")
                if [ "${RES_CREATE}" = "200" ] || [ "${RES_CREATE}" = "201" ]; then
                    log_ok "Администратор Navidrome (${ADMIN_USER}) успешно создан с мастер-паролем"
                    NAVIDROME_READY=1
                    break
                elif [ "${RES_CREATE}" = "400" ] || [ "${RES_CREATE}" = "409" ] || [ "${RES_CREATE}" = "403" ]; then
                    NAVIDROME_READY=1
                    break
                fi
            fi
            sleep 2
        done
        [ $NAVIDROME_READY -eq 1 ] && log_ok "Navidrome готов к работе (порт 4533 / ${MUSIC_DOMAIN})"
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

    if [[ "${ENABLE_TG_BOT:-Y}" =~ ^[Yy]$ ]]; then
        log_info "Настройка и запуск службы Telegram-бота (Медиа-загрузчик yt-dlp)..."
        mkdir -p "${APP_DIR}/scripts"

        cat << 'EOF_TG_BOT' > "${APP_DIR}/scripts/homelab-bot.py"
#!/usr/bin/env python3
# ==============================================================================
# Homelab Media Telegram Bot (2026 Native Daemon)
# Zero external pip dependencies: Python 3 stdlib + standalone yt-dlp + ffmpeg + curl
# Features:
# - Video download to ${SAVE_DIR}/downloads (MP4) -> Samba
# - Music extract to ${SAVE_DIR}/music (Hi-Fi MP3 with Cover Art & Tags) -> Navidrome
# - Direct audio send to Telegram Chat (<= 50MB) via Bot API
# - Server status (/status), help (/help), and security check by TELEGRAM_CHAT_ID
# ==============================================================================

import os
import sys
import time
import re
import json
import urllib.request
import urllib.parse
import urllib.error
import subprocess
import threading
import logging
import shutil
import uuid

ENV_PATH = "/opt/homelab/.env"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)

URL_CACHE = {}  # {url_id: {"url": str, "ts": float}}
URL_REGEX = re.compile(r'https?://[^\s<>"]+|www\.[^\s<>"]+')

def parse_env():
    conf = {
        "BOT_TOKEN": "",
        "CHAT_ID": "",
        "SAVE_DIR": "/opt/homelab/save",
        "LOCAL_IP": "127.0.0.1",
        "ADMIN_USER": "admin",
        "VERSION": "2.7.0"
    }
    if os.path.exists(ENV_PATH):
        try:
            with open(ENV_PATH, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip().strip("'\"")
                    v = v.replace("\\n", "\n").replace("\\t", "\t")
                    if k in ("SAVED_TELEGRAM_BOT_TOKEN", "TELEGRAM_BOT_TOKEN"):
                        conf["BOT_TOKEN"] = v
                    elif k in ("SAVED_TELEGRAM_CHAT_ID", "TELEGRAM_CHAT_ID"):
                        conf["CHAT_ID"] = str(v)
                    elif k in ("SAVED_SAVE_DIR", "SAVE_DIR"):
                        conf["SAVE_DIR"] = v
                    elif k in ("SAVED_LOCAL_IP", "LOCAL_IP"):
                        conf["LOCAL_IP"] = v
                    elif k in ("SAVED_ADMIN_USER", "ADMIN_USER"):
                        conf["ADMIN_USER"] = v
                    elif k in ("SAVED_HOMELAB_VERSION", "HOMELAB_VERSION"):
                        conf["VERSION"] = v
        except Exception as e:
            logging.error(f"Error parsing {ENV_PATH}: {e}")
    if not conf["BOT_TOKEN"] and os.environ.get("TELEGRAM_BOT_TOKEN"):
        conf["BOT_TOKEN"] = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not conf["CHAT_ID"] and os.environ.get("TELEGRAM_CHAT_ID"):
        conf["CHAT_ID"] = str(os.environ.get("TELEGRAM_CHAT_ID"))
    return conf

def tg_call(token, method, payload=None, timeout=30):
    url = f"https://api.telegram.org/bot{token}/{method}"
    data = None
    headers = {"Content-Type": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        return {"ok": False, "error": str(e)}

def send_msg(token, chat_id, text, reply_markup=None):
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    return tg_call(token, "sendMessage", payload, timeout=15)

def edit_msg(token, chat_id, message_id, text, reply_markup=None):
    payload = {
        "chat_id": chat_id,
        "message_id": message_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    return tg_call(token, "editMessageText", payload, timeout=15)

def answer_cb(token, query_id, text=None):
    payload = {"callback_query_id": query_id}
    if text:
        payload["text"] = text
    return tg_call(token, "answerCallbackQuery", payload, timeout=10)

def find_ytdlp():
    for p in ["/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]:
        if os.path.exists(p) and os.access(p, os.X_OK):
            return p
    return "yt-dlp"

def get_server_status(conf):
    uptime_str = "N/A"
    try:
        uptime_str = subprocess.check_output(["uptime", "-p"], stderr=subprocess.DEV_NULL).decode().strip()
    except Exception:
        pass

    ram_str = "N/A"
    try:
        out = subprocess.check_output(["free", "-h"], stderr=subprocess.DEV_NULL).decode()
        for line in out.splitlines():
            if line.startswith("Mem:"):
                parts = line.split()
                ram_str = f"{parts[2]} / {parts[1]}"
    except Exception:
        pass

    disk_str = "N/A"
    save_dir = conf.get("SAVE_DIR", "/opt/homelab/save")
    try:
        out = subprocess.check_output(["df", "-h", save_dir], stderr=subprocess.DEV_NULL).decode()
        lines = out.splitlines()
        if len(lines) >= 2:
            parts = lines[1].split()
            disk_str = f"{parts[2]} / {parts[1]} (свободно {parts[3]})"
    except Exception:
        pass

    ytdlp_ver = "N/A"
    try:
        ytdlp_ver = subprocess.check_output([find_ytdlp(), "--version"], stderr=subprocess.DEV_NULL).decode().strip()
    except Exception:
        pass

    containers_active = 0
    try:
        out = subprocess.check_output(["docker", "ps", "-q"], stderr=subprocess.DEV_NULL).decode().strip()
        if out:
            containers_active = len(out.splitlines())
    except Exception:
        pass

    msg = (
        f"🖥 <b>Homelab Appliance v{conf.get('VERSION', '2.7.0')}</b>\n"
        f"────────────────────────────\n"
        f"• <b>Аптайм:</b> {uptime_str}\n"
        f"• <b>ОЗУ:</b> {ram_str}\n"
        f"• <b>Диск ({save_dir}):</b> {disk_str}\n"
        f"• <b>Docker контейнеры:</b> {containers_active} активных\n"
        f"• <b>yt-dlp:</b> {ytdlp_ver}\n"
        f"• <b>IP адрес:</b> {conf.get('LOCAL_IP', '127.0.0.1')}\n"
        f"────────────────────────────\n"
        f"🎵 Музыка: <a href='https://music.lan'>music.lan</a> (Navidrome)\n"
        f"📂 Samba: <code>\\\\{conf.get('LOCAL_IP')}\\storage</code>\n"
    )
    return msg

def clean_url_cache():
    now = time.time()
    expired = [k for k, v in URL_CACHE.items() if now - v["ts"] > 86400]
    for k in expired:
        URL_CACHE.pop(k, None)

def worker_download_video(token, chat_id, message_id, url, conf):
    save_dir = conf.get("SAVE_DIR", "/opt/homelab/save")
    dl_dir = os.path.join(save_dir, "downloads")
    os.makedirs(dl_dir, exist_ok=True)
    edit_msg(token, chat_id, message_id, "⏳ <b>[1/2] Скачивание видео в MP4...</b>\nПожалуйста, подождите.")
    
    cmd = [
        find_ytdlp(),
        "--no-warnings",
        "--no-playlist",
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "--merge-output-format", "mp4",
        "-o", os.path.join(dl_dir, "%(title)s.%(ext)s"),
        url
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=600)
        if res.returncode == 0:
            edit_msg(token, chat_id, message_id,
                f"✅ <b>Видео успешно сохранено!</b>\n\n"
                f"📁 <b>Каталог:</b> <code>{dl_dir}</code>\n"
                f"💻 <b>Samba NAS:</b> <code>\\\\{conf.get('LOCAL_IP')}\\storage\\downloads</code>"
            )
        else:
            err = res.stderr[-400:] if res.stderr else "Неизвестная ошибка"
            edit_msg(token, chat_id, message_id, f"❌ <b>Ошибка при скачивании видео:</b>\n<pre>{err}</pre>")
    except Exception as e:
        edit_msg(token, chat_id, message_id, f"❌ <b>Исключение:</b> {str(e)}")

def worker_download_music(token, chat_id, message_id, url, conf):
    save_dir = conf.get("SAVE_DIR", "/opt/homelab/save")
    music_dir = os.path.join(save_dir, "music")
    os.makedirs(music_dir, exist_ok=True)
    edit_msg(token, chat_id, message_id, "⏳ <b>[1/2] Извлечение аудио Hi-Fi, обложки и тегов...</b>\nОбработка через ffmpeg...")
    
    cmd = [
        find_ytdlp(),
        "--no-warnings",
        "--no-playlist",
        "-x",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--embed-metadata",
        "--embed-thumbnail",
        "-o", os.path.join(music_dir, "%(artist,uploader)s/%(album,title)s/%(title)s.%(ext)s"),
        url
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=600)
        if res.returncode == 0:
            edit_msg(token, chat_id, message_id,
                f"✅ <b>Трек успешно добавлен в библиотеку!</b>\n\n"
                f"🎵 <b>Каталог Navidrome:</b> <code>{music_dir}</code>\n"
                f"🎧 <b>Стриминг:</b> Трек уже готов к воспроизведению в Symfonium, Substreamer и Feishin!"
            )
        else:
            err = res.stderr[-400:] if res.stderr else "Неизвестная ошибка"
            edit_msg(token, chat_id, message_id, f"❌ <b>Ошибка при сохранении музыки:</b>\n<pre>{err}</pre>")
    except Exception as e:
        edit_msg(token, chat_id, message_id, f"❌ <b>Исключение:</b> {str(e)}")

def worker_download_tg(token, chat_id, message_id, url, conf):
    work_id = uuid.uuid4().hex[:8]
    tmp_dir = f"/tmp/homelab_tg_{work_id}"
    os.makedirs(tmp_dir, exist_ok=True)
    save_dir = conf.get("SAVE_DIR", "/opt/homelab/save")
    music_dir = os.path.join(save_dir, "music")

    edit_msg(token, chat_id, message_id, "⏳ <b>[1/3] Загрузка и конвертация аудио в MP3...</b>")
    cmd = [
        find_ytdlp(),
        "--no-warnings",
        "--no-playlist",
        "-x",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--embed-metadata",
        "--embed-thumbnail",
        "-o", os.path.join(tmp_dir, "%(title)s.%(ext)s"),
        url
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=600)
        if res.returncode != 0:
            err = res.stderr[-400:] if res.stderr else "Неизвестная ошибка"
            edit_msg(token, chat_id, message_id, f"❌ <b>Ошибка при загрузке:</b>\n<pre>{err}</pre>")
            shutil.rmtree(tmp_dir, ignore_errors=True)
            return

        files = [os.path.join(tmp_dir, f) for f in os.listdir(tmp_dir) if f.lower().endswith(".mp3")]
        if not files:
            files = [os.path.join(tmp_dir, f) for f in os.listdir(tmp_dir) if os.path.isfile(os.path.join(tmp_dir, f))]
        
        if not files:
            edit_msg(token, chat_id, message_id, "❌ Файл аудио не найден после конвертации.")
            shutil.rmtree(tmp_dir, ignore_errors=True)
            return

        target_file = files[0]
        size_bytes = os.path.getsize(target_file)
        size_mb = size_bytes / (1024 * 1024)

        if size_bytes > 50 * 1024 * 1024:
            dest_name = os.path.basename(target_file)
            os.makedirs(music_dir, exist_ok=True)
            dest_path = os.path.join(music_dir, dest_name)
            shutil.move(target_file, dest_path)
            edit_msg(token, chat_id, message_id,
                f"⚠️ <b>Размер файла ({size_mb:.1f} МБ) превышает лимит Telegram (50 МБ).</b>\n\n"
                f"Файл сохранен на сервере в <code>/music/{dest_name}</code> и доступен в Navidrome!"
            )
        else:
            edit_msg(token, chat_id, message_id, f"📤 <b>[2/3] Отправка файла ({size_mb:.1f} МБ) в Telegram...</b>")
            title = os.path.splitext(os.path.basename(target_file))[0]
            curl_cmd = [
                "curl", "-s", "-S",
                "-F", f"chat_id={chat_id}",
                "-F", f"audio=@{target_file}",
                "-F", f"title={title}",
                "-F", "caption=🎵 Скачано через Homelab Bot",
                f"https://api.telegram.org/bot{token}/sendAudio"
            ]
            up_res = subprocess.run(curl_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180)
            if up_res.returncode == 0 and '"ok":true' in up_res.stdout:
                edit_msg(token, chat_id, message_id, f"✅ <b>Аудио успешно отправлено в чат!</b>")
            else:
                edit_msg(token, chat_id, message_id, f"❌ <b>Ошибка при передаче аудио:</b>\n<pre>{up_res.stdout[-300:]}</pre>")
    except Exception as e:
        edit_msg(token, chat_id, message_id, f"❌ <b>Исключение:</b> {str(e)}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)

def handle_update(upd, conf):
    token = conf["BOT_TOKEN"]
    owner_chat = str(conf["CHAT_ID"]).strip()

    if "callback_query" in upd:
        cq = upd["callback_query"]
        cq_id = cq["id"]
        from_id = str(cq.get("from", {}).get("id", ""))
        chat_id = str(cq.get("message", {}).get("chat", {}).get("id", ""))
        msg_id = cq.get("message", {}).get("message_id")
        data = cq.get("data", "")

        if owner_chat and from_id != owner_chat and chat_id != owner_chat:
            answer_cb(token, cq_id, "⛔ Доступ запрещен (чужой чат)")
            return

        parts = data.split(":", 1)
        if len(parts) == 2:
            act, uid = parts[0], parts[1]
            cached = URL_CACHE.get(uid)
            if not cached:
                answer_cb(token, cq_id, "Ссылка устарела. Отправьте ее повторно.")
                return
            
            url = cached["url"]
            answer_cb(token, cq_id, "Задача принята в обработку...")
            
            if act == "vid":
                threading.Thread(target=worker_download_video, args=(token, chat_id, msg_id, url, conf), daemon=True).start()
            elif act == "mus":
                threading.Thread(target=worker_download_music, args=(token, chat_id, msg_id, url, conf), daemon=True).start()
            elif act == "tg":
                threading.Thread(target=worker_download_tg, args=(token, chat_id, msg_id, url, conf), daemon=True).start()
        return

    if "message" in upd:
        msg = upd["message"]
        chat_id = str(msg.get("chat", {}).get("id", ""))
        from_id = str(msg.get("from", {}).get("id", ""))
        text = msg.get("text", "").strip()

        if owner_chat and from_id != owner_chat and chat_id != owner_chat:
            send_msg(token, chat_id, "⛔ <b>Доступ запрещен.</b>\nЭтот сервер Homelab привязан к другому пользователю.")
            return

        if text in ("/start", "/help"):
            welcome = (
                "👋 <b>Привет! Я персональный Homelab Медиа-бот.</b>\n\n"
                "Отправьте мне ссылку на видео или трек (YouTube, VK, RuTube, TikTok, SoundCloud и др.), "
                "и выберите нужный формат:\n\n"
                "• 🎬 <b>Видео (MP4)</b> — сохранение в папку <code>/downloads</code> (Samba)\n"
                "• 🎵 <b>Музыка (Hi-Fi)</b> — извлечение аудио с обложкой и тегами в <code>/music</code> (Navidrome)\n"
                "• 📥 <b>В чат TG</b> — прямая отправка MP3 файла сюда в диалог\n\n"
                "<b>Команды:</b>\n"
                "/status — Состояние сервера, RAM, диска и Docker\n"
                "/ping — Проверка отклика бота\n"
                "/help — Справка"
            )
            send_msg(token, chat_id, welcome)
            return

        if text == "/status":
            send_msg(token, chat_id, get_server_status(conf))
            return

        if text == "/ping":
            send_msg(token, chat_id, "Pong! 🏓 Бот работает в штатном режиме.")
            return

        urls = URL_REGEX.findall(text)
        if urls:
            url = urls[0]
            clean_url_cache()
            uid = uuid.uuid4().hex[:8]
            URL_CACHE[uid] = {"url": url, "ts": time.time()}

            kbd = {
                "inline_keyboard": [
                    [
                        {"text": "🎬 Видео (MP4)", "callback_data": f"vid:{uid}"},
                        {"text": "🎵 В Navidrome (Hi-Fi)", "callback_data": f"mus:{uid}"}
                    ],
                    [
                        {"text": "📥 Аудио прямо в чат TG", "callback_data": f"tg:{uid}"}
                    ]
                ]
            }
            send_msg(token, chat_id, f"🔗 <b>Ссылка получена!</b>\n<code>{url[:60]}...</code>\n\nВыберите действие:", reply_markup=kbd)
        elif text:
            send_msg(token, chat_id, "💡 Отправьте мне ссылку на видео или аудио для скачивания, либо используйте команду /status.")

def main():
    logging.info("Starting Homelab Telegram Media Bot Daemon...")
    last_env_check = 0
    conf = parse_env()
    offset = 0

    while True:
        now = time.time()
        if now - last_env_check > 30:
            last_env_check = now
            conf = parse_env()

        token = conf.get("BOT_TOKEN")
        if not token:
            logging.warning("TELEGRAM_BOT_TOKEN is not configured in .env. Waiting 30s...")
            time.sleep(30)
            continue

        try:
            res = tg_call(token, "getUpdates", {"offset": offset, "timeout": 25}, timeout=35)
            if res.get("ok"):
                for upd in res.get("result", []):
                    offset = upd["update_id"] + 1
                    try:
                        handle_update(upd, conf)
                    except Exception as err:
                        logging.error(f"Error handling update: {err}")
            else:
                logging.warning(f"Telegram API response: {res}")
                time.sleep(5)
        except Exception as e:
            logging.error(f"Polling loop exception: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
EOF_TG_BOT
        chmod 750 "${APP_DIR}/scripts/homelab-bot.py"

        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            cat <<EOF_BOT_SVC > /etc/systemd/system/homelab-bot.service
[Unit]
Description=Homelab Telegram Media Bot Daemon
After=network.target docker.service
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/scripts/homelab-bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_BOT_SVC
            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable homelab-bot.service >/dev/null 2>&1 || true
            systemctl restart homelab-bot.service >/dev/null 2>&1 || true
            log_ok "Служба Telegram-бота активирована (systemd: homelab-bot.service)"
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            cat <<EOF_BOT_RC > /etc/init.d/homelab-bot
#!/sbin/openrc-run
name="homelab-bot"
description="Homelab Telegram Media Bot Daemon"
command="/usr/bin/python3"
command_args="${APP_DIR}/scripts/homelab-bot.py"
command_background="yes"
pidfile="/run/homelab-bot.pid"
output_log="/var/log/homelab-bot.log"
error_log="/var/log/homelab-bot.err"

depend() {
    need net
    after firewall
}
EOF_BOT_RC
            chmod 755 /etc/init.d/homelab-bot
            rc-update add homelab-bot default >/dev/null 2>&1 || true
            rc-service homelab-bot restart >/dev/null 2>&1 || rc-service homelab-bot start >/dev/null 2>&1 || true
            log_ok "Служба Telegram-бота активирована (OpenRC: homelab-bot)"
        fi
    fi

    log_info "Установка консольной утилиты управления комплексом (/usr/local/bin/homelab)..."
    cat << 'EOF_HOMELAB_CLI' > /usr/local/bin/homelab
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
        *) echo "$s" ;;
    esac
}

cmd_status() {
    echo -e "${CLR_CYAN}${CLR_BOLD}╭── HOMELAB APPLIANCE: СТАТУС СИСТЕМЫ И СЕРВИСОВ ───────────────${CLR_RESET}"
    echo -e "  ${CLR_WHITE}• Версия комплекса:${CLR_RESET}  ${CLR_GREEN}v${SAVED_HOMELAB_VERSION:-2.5.0}${CLR_RESET}"
    echo -e "  ${CLR_WHITE}• Ядро / ОС:${CLR_RESET}         $(uname -srm) [$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || echo 'Linux')]"
    echo -e "  ${CLR_WHITE}• Аптайм хоста:${CLR_RESET}      $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}' | tr -d ',')"
    local ram_usage
    ram_usage=$(free -h 2>/dev/null | awk '/^Mem:/{print $3 " / " $2}')
    local storage_usage
    storage_usage=$(df -h "${SAVED_SAVE_DIR:-/opt/homelab/save}" 2>/dev/null | awk 'NR==2{print $3 " / " $2 " (свободно " $4 ")"}')
    echo -e "  ${CLR_WHITE}• Использование ОЗУ:${CLR_RESET} ${ram_usage:-N/A}"
    echo -e "  ${CLR_WHITE}• Хранилище:${CLR_RESET}         ${storage_usage:-N/A}"
    
    local FW_STATUS="не активен"
    if command -v nft >/dev/null 2>&1 && nft list table inet homelab >/dev/null 2>&1; then
        FW_STATUS="${CLR_GREEN}nftables (таблица inet homelab)${CLR_RESET}"
    fi
    echo -e "  ${CLR_WHITE}• Фаервол / NAT:${CLR_RESET}     ${FW_STATUS}"

    local BOT_STATUS="${CLR_DIM}не настроен${CLR_RESET}"
    if [ -f /etc/systemd/system/homelab-bot.service ] || [ -f /etc/init.d/homelab-bot ]; then
        if pgrep -f "homelab-bot.py" >/dev/null 2>&1; then
            BOT_STATUS="${CLR_GREEN}Активен (Telegram Media Bot)${CLR_RESET}"
        else
            BOT_STATUS="${CLR_YELLOW}Остановлен / Ожидает токен в .env${CLR_RESET}"
        fi
    fi
    echo -e "  ${CLR_WHITE}• Telegram-бот:${CLR_RESET}      ${BOT_STATUS}"
    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
    echo ""

    echo -e "${CLR_CYAN}${CLR_BOLD}╭── СТАТУС КОНТЕЙНЕРОВ DOCKER ─────────────────────────────────${CLR_RESET}"
    printf "  %-18s %-12s %-14s %-10s\n" "СЕРВИС" "СТАТУС" "ЗДОРОВЬЕ" "ПАМЯТЬ"
    echo -e "  ─────────────────────────────────────────────────────────────"
    
    local CONTAINERS=("adguardhome" "mihomo" "caddy" "vaultwarden" "gitea" "qbittorrent" "navidrome" "samba" "dozzle" "watchtower" "autoheal")
    for c in "${CONTAINERS[@]}"; do
        if docker inspect "$c" >/dev/null 2>&1; then
            local state
            state=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "stopped")
            local health
            health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo "none")
            local mem
            mem=$(docker stats --no-stream --format "{{.MemUsage}}" "$c" 2>/dev/null | cut -d/ -f1 | tr -d ' ' || echo "N/A")
            
            local state_str="${CLR_GREEN}Running${CLR_RESET}"
            [ "$state" != "running" ] && state_str="${CLR_RED}${state}${CLR_RESET}"
            
            local health_str="${CLR_DIM}—${CLR_RESET}"
            [ "$health" = "healthy" ] && health_str="${CLR_GREEN}Healthy${CLR_RESET}"
            [ "$health" = "starting" ] && health_str="${CLR_YELLOW}Starting${CLR_RESET}"
            [ "$health" = "unhealthy" ] && health_str="${CLR_RED}UNHEALTHY${CLR_RESET}"
            
            printf "  %-18s %-22b %-24b %-10s\n" "$c" "$state_str" "$health_str" "${mem:-N/A}"
        fi
    done
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
    fi

    if [ -x /usr/local/bin/yt-dlp ] || command -v yt-dlp >/dev/null 2>&1; then
        local YV
        YV=$(yt-dlp --version 2>/dev/null || /usr/local/bin/yt-dlp --version 2>/dev/null || echo "v2026")
        echo -e "  ${TAG_OK} Медиа-загрузчик yt-dlp (standalone):     ${CLR_GREEN}[ГОТОВ (${YV})]${CLR_RESET}"
    fi

    if [ -f /etc/systemd/system/homelab-bot.service ] || [ -f /etc/init.d/homelab-bot ]; then
        if pgrep -f "homelab-bot.py" >/dev/null 2>&1; then
            echo -e "  ${TAG_OK} Telegram Медиа-бот (homelab-bot):         ${CLR_GREEN}[АКТИВЕН И СЛУШАЕТ ЧАТ]${CLR_RESET}"
        else
            echo -e "  ${TAG_WARN} Telegram Медиа-бот (homelab-bot):         ${CLR_YELLOW}[ОСТАНОВЛЕН / ОЖИДАЕТ НАСТРОЙКИ В .env]${CLR_RESET}"
        fi
    fi

    echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
}

cmd_update() {
    echo -e "  ${TAG_INFO} Проверка и загрузка свежих версий Docker-образов..."
    (cd "$APP_DIR" && dc_cmd pull)
    echo -e "  ${TAG_INFO} Пересоздание контейнеров с новыми образами..."
    (cd "$APP_DIR" && dc_cmd up -d --remove-orphans)
    echo -e "  ${TAG_INFO} Очистка неиспользуемых устаревших слоёв..."
    docker image prune -f >/dev/null 2>&1 || true
    echo -e "  ${TAG_OK} Стек Homelab успешно обновлен до последних версий!"
}

cmd_version() {
    echo -e "${CLR_CYAN}${CLR_BOLD}╭── ВЕРСИЯ И СТАТУС ОБНОВЛЕНИЙ HOMELAB ───────────────────────${CLR_RESET}"
    local CUR_VER="${SAVED_HOMELAB_VERSION:-2.5.0}"
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
    local CUR_VER="${SAVED_HOMELAB_VERSION:-2.5.0}"
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

    tar -czf "${SNAP_TAR}" \
        -C "${APP_DIR}" \
        .env compose.yaml Caddyfile \
        2>/dev/null || true
    [ -d "${APP_DIR}/mihomo" ] && tar -rf "${SNAP_TAR}" -C "${APP_DIR}" mihomo/config.yaml 2>/dev/null || true
    [ -d "${APP_DIR}/adguard/conf" ] && tar -rf "${SNAP_TAR}" -C "${APP_DIR}" adguard/conf/AdGuardHome.yaml 2>/dev/null || true
    [ -d "${APP_DIR}/configs/navidrome" ] && tar -rf "${SNAP_TAR}" -C "${APP_DIR}" configs/navidrome 2>/dev/null || true
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
        return 0
    else
        echo -e "  ${TAG_ERR} В процессе обновления произошла ошибка!"
        echo -e "  Для отката к исходному состоянию выполните: ${CLR_GREEN}homelab rollback${CLR_RESET}"
        echo -e "${CLR_CYAN}╰─────────────────────────────────────────────────────────────${CLR_RESET}"
        return 1
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

        local ALL_CONTAINERS=("adguardhome" "mihomo" "caddy" "dozzle" "watchtower" "autoheal" "vaultwarden" "gitea" "qbittorrent" "navidrome" "samba")
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
        echo "                  ЖУРНАЛ TELEGRAM-БОТА (HOMELAB-BOT)                         "
        echo "============================================================================="
        if [ -f /var/log/homelab-bot.log ]; then
            tail -n 100 /var/log/homelab-bot.log 2>/dev/null || echo "Лог бота пуст"
        elif command -v journalctl >/dev/null 2>&1; then
            journalctl -u homelab-bot.service -n 100 --no-pager 2>/dev/null || echo "Записей бота в journald не обнаружено"
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

cmd_bot() {
    local action="${1:-status}"
    shift || true
    case "$action" in
        status)
            echo -e "  ${TAG_INFO} Статус службы Homelab Telegram Bot:"
            if command -v systemctl >/dev/null 2>&1; then
                systemctl status homelab-bot.service --no-pager 2>/dev/null || echo "Служба homelab-bot не активна"
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service homelab-bot status 2>/dev/null || echo "Служба homelab-bot не активна"
            fi
            ;;
        start)
            echo -e "  ${TAG_INFO} Запуск службы Telegram-бота..."
            if command -v systemctl >/dev/null 2>&1; then
                systemctl start homelab-bot.service
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service homelab-bot start
            fi
            echo -e "  ${TAG_OK} Служба запущена"
            ;;
        stop)
            echo -e "  ${TAG_INFO} Остановка службы Telegram-бота..."
            if command -v systemctl >/dev/null 2>&1; then
                systemctl stop homelab-bot.service
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service homelab-bot stop
            fi
            echo -e "  ${TAG_OK} Служба остановлена"
            ;;
        restart)
            echo -e "  ${TAG_INFO} Перезапуск службы Telegram-бота..."
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart homelab-bot.service
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service homelab-bot restart
            fi
            echo -e "  ${TAG_OK} Служба перезапущена"
            ;;
        logs)
            echo -e "  ${TAG_INFO} Просмотр журналов Telegram-бота:"
            if command -v journalctl >/dev/null 2>&1; then
                journalctl -u homelab-bot.service "$@" --no-pager
            elif [ -f /var/log/homelab-bot.log ]; then
                tail "$@" /var/log/homelab-bot.log
            fi
            ;;
        *)
            echo -e "Использование: ${CLR_GREEN}homelab bot [status|start|stop|restart|logs]${CLR_RESET}"
            ;;
    esac
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
    echo -e "  ${CLR_WHITE}bot [действие]${CLR_RESET}      Управление Telegram-ботом медиа (start|stop|restart|logs|status)"
    echo -e "  ${CLR_WHITE}doctor${CLR_RESET}              Комплексная самодиагностика DNS, TUN, NAT и прав"
    echo -e "  ${CLR_WHITE}backup${CLR_RESET}              Запуск горячего бэкапа баз данных прямо сейчас"
    echo -e "  ${CLR_WHITE}notify [текст]${CLR_RESET}      Отправить тестовое оповещение в Telegram"
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
    bot|tg-bot) shift; cmd_bot "$@" ;;
    backup) cmd_backup ;;
    doctor|check) cmd_doctor ;;
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
    chmod 755 /usr/local/bin/homelab

    cat << 'EOF_MIHOMO_BIN' > /usr/local/bin/mihomo
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
    chmod 755 /usr/local/bin/mihomo 2>/dev/null || true

    cat << 'EOF_ADGUARD_BIN' > /usr/local/bin/adguard
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
    chmod 755 /usr/local/bin/adguard 2>/dev/null || true
    ln -sf /usr/local/bin/adguard /usr/local/bin/adguardhome 2>/dev/null || true

    log_ok "Сервисы комплекса успешно запущены и готовы к работе"
    log_ok "Службы автозапуска и горячего резервного копирования активированы"
}
