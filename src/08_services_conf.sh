#!/usr/bin/env bash
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
        local IP_OCTET
        IP_OCTET=$(echo "${LOCAL_IP}" | awk -F. '{print $4}')
        local IP_PREFIX
        IP_PREFIX=$(echo "${LOCAL_IP}" | awk -F. '{print $1"."$2"."$3}')
        [ -z "${IP_PREFIX}" ] && IP_PREFIX="192.168.1"
        local AGH_RANGE_START="${IP_PREFIX}.50"
        local AGH_RANGE_END="${IP_PREFIX}.250"
        if [ -n "${IP_OCTET}" ] && [ "${IP_OCTET}" -ge 50 ] && [ "${IP_OCTET}" -le 149 ]; then
            AGH_RANGE_START="${IP_PREFIX}.$(( IP_OCTET + 1 ))"
        elif [ -n "${IP_OCTET}" ] && [ "${IP_OCTET}" -ge 150 ] && [ "${IP_OCTET}" -le 250 ]; then
            AGH_RANGE_END="${IP_PREFIX}.$(( IP_OCTET - 1 ))"
        fi
        local AGH_DHCP_ENABLED="false"
        [ "${ROUTER_MODE:-1}" = "2" ] && AGH_DHCP_ENABLED="true"

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
  aaaa_disabled: true
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
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: "AdGuard DNS filter"
    id: 1
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: "AdGuard Tracking Protection filter"
    id: 2
  - enabled: true
    url: https://raw.githubusercontent.com/dimisa-ru/anti-ad-filters/master/anti-ad.txt
    name: "Anti-AD (RU / CIS)"
    id: 3
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
dhcp:
  enabled: ${AGH_DHCP_ENABLED}
  interface_name: "${LAN_IFACE:-$DEFAULT_IFACE}"
  local_domain_name: "lan"
  dhcpv4:
    gateway_ip: "${LOCAL_IP}"
    subnet_mask: "255.255.255.0"
    range_start: "${AGH_RANGE_START}"
    range_end: "${AGH_RANGE_END}"
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
    static_leases:
      - mac: "00:00:00:00:00:01"
        ip: "${IP_PREFIX}.1"
        hostname: "OpenWrt-Router"
      - mac: "00:00:00:00:00:05"
        ip: "${IP_PREFIX}.5"
        hostname: "Keenetic-Router"
  dhcpv6:
    enabled: false
EOF_AGH
        fi

        # Копирование конфигурации AdGuard Home в системный каталог OpenRC
        mkdir -p /var/lib/adguardhome
        cp -f "${AGH_CONF}" /var/lib/adguardhome/AdGuardHome.yaml 2>/dev/null || true
        chown -R adguardhome:adguardhome /var/lib/adguardhome 2>/dev/null || true

        log_info "Формирование конфигурации sing-box TUN (Mixed-Stack, Clash API и умная маршрутизация)..."
        mkdir -p /etc/sing-box /var/lib/sing-box "${APP_DIR}/sing-box"

        cat <<EOF_SINGBOX > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "output": "/var/log/sing-box.log",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "local",
        "tag": "dns-direct"
      },
      {
        "type": "udp",
        "tag": "dns-remote",
        "server": "77.88.8.8"
      }
    ]
  },
  "inbounds": [
    {
      "type": "direct",
      "tag": "dns-in",
      "listen": "127.0.0.1",
      "listen_port": 1053
    },
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": false,
      "stack": "mixed"
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": 7890
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "PROXY",
      "outbounds": [
        "direct"
      ]
    },
    {
      "type": "selector",
      "tag": "AI-Services",
      "outbounds": [
        "PROXY",
        "direct"
      ]
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "PROXY",
    "default_domain_resolver": "dns-direct",
    "rules": [
      {
        "action": "sniff"
      },
      {
        "inbound": [
          "dns-in"
        ],
        "action": "hijack-dns"
      },
      {
        "port": [
          53
        ],
        "outbound": "direct"
      },
      {
        "network": "udp",
        "port": [
          443
        ],
        "outbound": "block"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      },
      {
        "domain_suffix": [
          "ru",
          "su",
          "xn--p1ai",
          "xn--80asehdb",
          "xn--80aswg",
          "xn--80adxhks",
          "xn--c1avg",
          "gosuslugi.org",
          "gosuslugi.ru",
          "emias.info",
          "yandex.ru",
          "yandex.net",
          "yastatic.net",
          "vk.com",
          "userapi.com",
          "vk-portal.net",
          "vk-cdn.net",
          "vkusercontent.com",
          "ozonusercontent.com",
          "wbstatic.net",
          "avito.st",
          "2gis.com",
          "4pda.to",
          "ntc.party",
          "lan",
          "duckdns.org",
          "connectivitycheck.gstatic.com",
          "connectivitycheck.android.com",
          "clients3.google.com",
          "play.googleapis.com",
          "captive.apple.com",
          "connect.rom.miui.com",
          "wifi.miui.com",
          "connectivity.samsung.com.cn",
          "msftconnecttest.com",
          "msftncsi.com"
        ],
        "outbound": "direct"
      },
      {
        "domain_suffix": [
          "openai.com",
          "chatgpt.com",
          "oaistatic.com",
          "oaiusercontent.com",
          "anthropic.com",
          "claude.ai",
          "perplexity.ai",
          "gemini.google.com",
          "aistudio.google.com",
          "generativelanguage.googleapis.com",
          "cursor.com",
          "cursor.sh",
          "copilot.microsoft.com",
          "suno.com",
          "suno.ai",
          "midjourney.com",
          "x.ai",
          "grok.com",
          "deepseek.com",
          "v0.dev",
          "huggingface.co"
        ],
        "outbound": "AI-Services"
      },
      {
        "domain_suffix": [
          "googlevideo.com",
          "youtube.com",
          "youtu.be",
          "ytimg.com",
          "ggpht.com",
          "gvt1.com",
          "youtube-nocookie.com",
          "youtubekids.com",
          "discord.com",
          "discord.gg",
          "discordapp.com",
          "discordapp.net",
          "discord.media",
          "discordcdn.com",
          "t.me",
          "telegram.org",
          "telegram.me",
          "telegra.ph",
          "instagram.com",
          "cdninstagram.com",
          "facebook.com",
          "fbcdn.net",
          "meta.com",
          "twitter.com",
          "x.com",
          "twimg.com",
          "linkedin.com",
          "notion.so",
          "notion.site",
          "rutracker.org",
          "rutracker.net",
          "rutracker.nl",
          "t-ru.org",
          "nnmclub.to",
          "nnm-club.me",
          "rutor.info",
          "rutor.is",
          "opentor.org",
          "flibusta.is",
          "flibusta.site",
          "libria.fun",
          "anilibria.top"
        ],
        "outbound": "PROXY"
      }
    ],
    "auto_detect_interface": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "0.0.0.0:9090",
      "external_ui": "${APP_DIR}/mihomo/ui",
      "secret": "${MIHOMO_SECRET}",
      "default_mode": "rule"
    }
  }
}
EOF_SINGBOX
        cp -f /etc/sing-box/config.json "${APP_DIR}/sing-box/config.json" 2>/dev/null || true

        # Скрипт автоматического обновления подписок в sing-box
        cat << 'EOF_SUB_PY' > "${APP_DIR}/scripts/update_singbox_sub.py"
#!/usr/bin/env python3
import sys, os, json, re, urllib.request, urllib.parse, ssl, base64, subprocess

sub_url = sys.argv[1].strip() if len(sys.argv) > 1 else ""
config_path = "/etc/sing-box/config.json"

if not sub_url or sub_url in ("none", "direct", "-"):
    sys.exit(0)

ctx = ssl._create_unverified_context()

urls_to_try = []
if "fmt=" in sub_url:
    urls_to_try.append(re.sub(r'fmt=[^&]+', 'fmt=sing-box', sub_url))
else:
    sep = "&" if "?" in sub_url else "?"
    urls_to_try.append(f"{sub_url}{sep}fmt=sing-box")
urls_to_try.append(sub_url)

content = ""
for u in urls_to_try:
    try:
        req = urllib.request.Request(
            u,
            headers={
                "User-Agent": "sing-box/1.13.11",
                "Accept": "application/json, text/plain, */*"
            }
        )
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            data_str = resp.read().decode("utf-8", errors="ignore").strip()
            if data_str:
                content = data_str
                # Если уже получили JSON с outbounds, дальше можно не искать
                if '"outbounds"' in data_str:
                    break
    except Exception:
        continue

if not content:
    print("[-] Не удалось загрузить содержимое подписки")
    sys.exit(1)

PROXY_TYPES = {"vless", "vmess", "trojan", "shadowsocks", "hysteria", "hysteria2", "tuic", "wireguard"}

new_outbounds = []

# 1. Попытка парсинга как нативный JSON sing-box
try:
    if content.startswith("{") or content.startswith("["):
        parsed_json = json.loads(content)
        if isinstance(parsed_json, dict) and "outbounds" in parsed_json:
            for o in parsed_json["outbounds"]:
                if isinstance(o, dict) and o.get("type") in PROXY_TYPES:
                    new_outbounds.append(o)
        elif isinstance(parsed_json, list):
            for item in parsed_json:
                if isinstance(item, dict) and item.get("type") in PROXY_TYPES:
                    new_outbounds.append(item)
                elif isinstance(item, dict) and "outbounds" in item:
                    for o in item["outbounds"]:
                        if isinstance(o, dict) and o.get("type") in PROXY_TYPES:
                            new_outbounds.append(o)
except Exception:
    pass

# 2. Если JSON не содержал нод, пробуем base64-декодирование списка ссылок
if not new_outbounds:
    clean_c = "".join(content.split())
    try:
        padded = clean_c + "=" * (-len(clean_c) % 4)
        decoded = base64.b64decode(padded).decode("utf-8", errors="ignore")
        if "://" in decoded:
            content = decoded
    except Exception:
        pass

    def parse_proxy_uri(uri):
        uri = uri.strip()
        if uri.startswith("vless://"):
            m = re.match(r"vless://([^@]+)@([^:]+):(\d+)\?([^#]+)(?:#(.*))?", uri)
            if m:
                uuid, server, port, query_str, name = m.groups()
                params = dict(q.split("=", 1) for q in query_str.split("&") if "=" in q)
                tag = urllib.parse.unquote(name).strip() if name else f"vless-{server}"
                outbound = {
                    "type": "vless",
                    "tag": tag,
                    "server": server,
                    "server_port": int(port),
                    "uuid": uuid,
                    "packet_encoding": "xudp"
                }
                if params.get("security") == "reality":
                    outbound["tls"] = {
                        "enabled": True,
                        "server_name": params.get("sni", server),
                        "utls": {"enabled": True, "fingerprint": params.get("fp", "chrome")},
                        "reality": {
                            "enabled": True,
                            "public_key": params.get("pbk", ""),
                            "short_id": params.get("sid", "")
                        }
                    }
                elif params.get("security") == "tls":
                    outbound["tls"] = {
                        "enabled": True,
                        "server_name": params.get("sni", server),
                        "utls": {"enabled": True, "fingerprint": params.get("fp", "chrome")}
                    }
                net = params.get("type", "tcp")
                if net in ("ws", "websocket"):
                    outbound["transport"] = {
                        "type": "ws",
                        "path": params.get("path", "/"),
                        "headers": {"Host": params.get("host", server)}
                    }
                elif net == "grpc":
                    outbound["transport"] = {
                        "type": "grpc",
                        "service_name": params.get("serviceName", "")
                    }
                return outbound
        elif uri.startswith("trojan://"):
            m = re.match(r"trojan://([^@]+)@([^:]+):(\d+)(?:\?([^#]+))?(?:#(.*))?", uri)
            if m:
                password, server, port, query_str, name = m.groups()
                params = dict(q.split("=", 1) for q in (query_str or "").split("&") if "=" in q)
                tag = urllib.parse.unquote(name).strip() if name else f"trojan-{server}"
                outbound = {
                    "type": "trojan",
                    "tag": tag,
                    "server": server,
                    "server_port": int(port),
                    "password": password
                }
                outbound["tls"] = {
                    "enabled": True,
                    "server_name": params.get("sni", server),
                    "utls": {"enabled": True, "fingerprint": params.get("fp", "chrome")}
                }
                return outbound
        return None

    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        out = parse_proxy_uri(line)
        if out:
            new_outbounds.append(out)

# 3. Применение полученных серверов к конфигурации sing-box
if new_outbounds and os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)

        # Гарантируем уникальность тегов
        seen_tags = set()
        deduped = []
        for o in new_outbounds:
            orig_tag = o.get("tag", "proxy")
            tag = orig_tag
            idx = 2
            while tag in seen_tags:
                tag = f"{orig_tag}-{idx}"
                idx += 1
            o["tag"] = tag
            seen_tags.add(tag)
            deduped.append(o)

        proxy_tags = [o["tag"] for o in deduped]

        # Формируем гарантированный список системных outbounds с балансировщиком
        auto_outbound = {
            "type": "urltest",
            "tag": "auto",
            "outbounds": proxy_tags,
            "url": "https://cp.cloudflare.com/generate_204",
            "interval": "3m",
            "tolerance": 50
        }
        proxy_selector = {
            "type": "selector",
            "tag": "PROXY",
            "outbounds": ["auto"] + proxy_tags + ["direct"]
        }
        ai_selector = {
            "type": "selector",
            "tag": "AI-Services",
            "outbounds": ["auto"] + proxy_tags + ["direct"]
        }
        direct_outbound = {"type": "direct", "tag": "direct"}
        block_outbound = {"type": "block", "tag": "block"}

        cfg["outbounds"] = [proxy_selector, auto_outbound, ai_selector, direct_outbound, block_outbound] + deduped
        cfg.setdefault("route", {})
        cfg["route"]["final"] = "PROXY"

        # Гарантируем наличие dns-in inbound и hijack-dns для AdGuard Home
        inbounds = cfg.get("inbounds", [])
        if not any(ib.get("tag") == "dns-in" for ib in inbounds):
            inbounds.append({
                "type": "direct",
                "tag": "dns-in",
                "listen": "127.0.0.1",
                "listen_port": 1053
            })
        cfg["inbounds"] = inbounds

        route = cfg.get("route", {})
        rules = route.get("rules", [])
        if not any(r.get("action") == "hijack-dns" and "dns-in" in r.get("inbound", []) for r in rules):
            rules.insert(0, {
                "inbound": ["dns-in"],
                "action": "hijack-dns"
            })
        route["rules"] = rules
        cfg["route"] = route

        cfg.setdefault("log", {})
        cfg["log"]["output"] = "/var/log/sing-box.log"
        cfg["log"]["level"] = "info"
        cfg["log"]["timestamp"] = True

        # Проверка валидности конфигурации утилитой sing-box check
        test_path = config_path + ".test"
        with open(test_path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)

        res = subprocess.run(["sing-box", "check", "-c", test_path], capture_output=True, text=True)
        if res.returncode == 0:
            os.replace(test_path, config_path)
            print(f"[+] Успешно импортировано {len(deduped)} прокси-серверов в sing-box")
            # Перезапуск службы sing-box
            if os.path.exists("/etc/init.d/sing-box"):
                subprocess.run(["rc-service", "sing-box", "restart"], capture_output=True)
            elif os.path.exists("/usr/bin/systemctl"):
                subprocess.run(["systemctl", "restart", "sing-box"], capture_output=True)
        else:
            if os.path.exists(test_path):
                os.remove(test_path)
            print(f"[-] Ошибка валидации конфигурации sing-box: {res.stderr}")
            sys.exit(1)
    except Exception as e:
        print(f"[-] Ошибка обновления sing-box: {e}")
        sys.exit(1)
else:
    print("[-] Подходящих прокси-серверов в подписке не найдено.")
EOF_SUB_PY
        chmod 755 "${APP_DIR}/scripts/update_singbox_sub.py" 2>/dev/null || true

        if [ -n "${SUB_URL}" ] && [ "${SUB_URL}" != "none" ]; then
            python3 "${APP_DIR}/scripts/update_singbox_sub.py" "${SUB_URL}" 2>/dev/null || true
        fi
    fi
    log_ok "Конфигурации шлюза AdGuard Home и sing-box успешно сгенерированы"
}
