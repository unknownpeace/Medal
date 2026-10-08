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

        cat <<EOF_AGH > "${APP_DIR}/adguard/conf/AdGuardHome.yaml"
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
      - US-AUTO
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

  - name: US-AUTO
    type: url-test
    use:
      - my-sub
    proxies:
      - AUTO
    filter: \"(?i)\\\\b(US|USA|United States|America)\\\\b|🇺🇸|США\"
    url: https://cp.cloudflare.com/generate_204
    interval: 300
    tolerance: 50
    lazy: true

  - name: YouTube
    type: select
    proxies:
      - AUTO
      - PROXY
      - DIRECT
    use:
      - my-sub

  - name: Discord
    type: select
    proxies:
      - AUTO
      - PROXY
      - DIRECT
    use:
      - my-sub

  - name: Telegram
    type: select
    proxies:
      - AUTO
      - PROXY
      - DIRECT
    use:
      - my-sub

  - name: AI-Services
    type: select
    proxies:
      - US-AUTO
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

  - name: US-AUTO
    type: select
    proxies:
      - DIRECT

  - name: YouTube
    type: select
    proxies:
      - DIRECT

  - name: Discord
    type: select
    proxies:
      - DIRECT

  - name: Telegram
    type: select
    proxies:
      - DIRECT

  - name: AI-Services
    type: select
    proxies:
      - US-AUTO
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

  # YouTube и Google Video CDN — через группу YouTube (без замедления РКН)
  - DOMAIN-SUFFIX,googlevideo.com,YouTube
  - DOMAIN-SUFFIX,youtube.com,YouTube
  - DOMAIN-SUFFIX,youtu.be,YouTube
  - DOMAIN-SUFFIX,ytimg.com,YouTube
  - DOMAIN-SUFFIX,ggpht.com,YouTube
  - DOMAIN-SUFFIX,gvt1.com,YouTube
  - DOMAIN-SUFFIX,youtube-nocookie.com,YouTube
  - DOMAIN-SUFFIX,youtubekids.com,YouTube
  - RULE-SET,youtube_site,YouTube

  # Discord (голосовые серверы RTC, чаты, вложения, шлюз) — через группу Discord
  - DOMAIN-SUFFIX,discord.com,Discord
  - DOMAIN-SUFFIX,discord.gg,Discord
  - DOMAIN-SUFFIX,discordapp.com,Discord
  - DOMAIN-SUFFIX,discordapp.net,Discord
  - DOMAIN-SUFFIX,discord.media,Discord
  - DOMAIN-SUFFIX,discordcdn.com,Discord
  - DOMAIN-KEYWORD,discord,Discord
  - RULE-SET,discord_site,Discord

  # Telegram — через группу Telegram
  - DOMAIN-SUFFIX,t.me,Telegram
  - DOMAIN-SUFFIX,telegram.org,Telegram
  - DOMAIN-SUFFIX,telegram.me,Telegram
  - DOMAIN-SUFFIX,telegra.ph,Telegram
  - RULE-SET,telegram_site,Telegram

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
