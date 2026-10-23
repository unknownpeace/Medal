# Modern sing-box (v1.11+) Configuration Blueprint

```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "0.0.0.0:9090",
      "external_ui": "/opt/homelab/mihomo/ui",
      "secret": "<SECRET>",
      "default_mode": "rule"
    }
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": false,
      "stack": "system",
      "sniff": true,
      "sniff_override_destination": false
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "PROXY",
      "outbounds": ["auto", "DIRECT", "...nodes..."],
      "default": "auto"
    },
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": ["...nodes..."],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "3m",
      "tolerance": 50
    },
    {
      "type": "direct",
      "tag": "DIRECT"
    },
    {
      "type": "block",
      "tag": "BLOCK"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "dns-out" },
      { "ip_is_private": true, "outbound": "DIRECT" },
      { "domain_suffix": [".ru", ".su", ".xn--p1ai", "yandex.net", "vk.com", "gosuslugi.ru", "sberbank.ru"], "outbound": "DIRECT" },
      { "domain_suffix": ["youtube.com", "googlevideo.com", "ytimg.com", "discord.com", "openai.com", "anthropic.com"], "outbound": "PROXY" }
    ],
    "auto_detect_interface": true,
    "final": "PROXY"
  }
}
```
