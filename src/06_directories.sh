#!/usr/bin/env bash
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
    chown -R "${USER_UID}:${USER_GID}" "${SAVE_DIR}/downloads" 2>/dev/null || true
    chmod 775 "${SAVE_DIR}/downloads" 2>/dev/null || true

    if [[ "${ENABLE_NAVIDROME}" =~ ^[Yy]$ ]]; then
        mkdir -p "${SAVE_DIR}/music" "${APP_DIR}/configs/navidrome"
        apply_nocow_helper "${APP_DIR}/configs/navidrome"
        apply_nocow_helper "${SAVE_DIR}/music"
        chown -R "${USER_UID}:${USER_GID}" "${SAVE_DIR}/music" "${APP_DIR}/configs/navidrome" 2>/dev/null || true
        chmod 775 "${SAVE_DIR}/music" 2>/dev/null || true
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
    'https://mirror.ghproxy.com/https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip',
    'https://ghproxy.net/https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip',
    'https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip'
]
zip_p = '/tmp/vuetorrent.zip'
dest = '${APP_DIR}/qbittorrent/vuetorrent'
os.makedirs(dest, exist_ok=True)

for u in urls:
    try:
        req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=8) as resp, open(zip_p, 'wb') as f:
            f.write(resp.read())
        if os.path.isfile(zip_p) and os.path.getsize(zip_p) > 50000:
            break
    except Exception:
        pass

if os.path.isfile(zip_p) and os.path.getsize(zip_p) > 50000:
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
        
        local ALT_UI_FLAG="false"
        [ "${VUETORRENT_OK}" -eq 1 ] && ALT_UI_FLAG="true"

        cat <<EOF_QBIT_CONF > "${APP_DIR}/qbittorrent/config/qBittorrent/qBittorrent.conf"
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
        chown -R "${USER_UID}:${USER_GID}" "${APP_DIR}/qbittorrent" 2>/dev/null || true
    fi

    chown -R "${USER_UID}:${USER_GID}" "${SAVE_DIR}" 2>/dev/null || true

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
                    'https://mirror.ghproxy.com/https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz'
                    'https://ghproxy.net/https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz'
                    'https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz'
                    'https://ghfast.top/https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.tar.gz'
                )
                local tar_tmp="/tmp/metacubexd.tar.gz"
                for u in "${urls[@]}"; do
                    if curl -fsSL -4 -k --connect-timeout 3 -m 10 "$u" -o "$tar_tmp" 2>/dev/null && [ -s "$tar_tmp" ]; then
                        if [[ "$u" =~ compressed-dist ]]; then
                            tar -xzf "$tar_tmp" -C "${APP_DIR}/mihomo/ui" 2>/dev/null && rm -f "$tar_tmp" && return 0
                        else
                            tar -xzf "$tar_tmp" -C "${APP_DIR}/mihomo/ui" --strip-components=1 2>/dev/null && rm -f "$tar_tmp" && return 0
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
