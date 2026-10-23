---
name: alpine-baremetal-appliance
description: >-
  Design, optimize, and maintain zero-docker bare-metal server appliances and micro-services
  on Alpine Linux with OpenRC. Use when configuring OpenRC services, supervise-daemon,
  Caddy 2 reverse proxy with local PKI, Vaultwarden, Forgejo, Navidrome, Samba,
  capabilities, or memory optimizations.
---

# Alpine Bare-Metal Appliance Skill

Runbook and architecture reference for managing native, Zero-Docker OpenRC services on Alpine Linux with minimal memory footprints (< 600 MB RAM for entire 10-service homelab stacks).

## Key Components & Service Mapping

| Service | OpenRC Service Name | Config Path | Port | Native Binary |
| :--- | :--- | :--- | :--- | :--- |
| **sing-box** | `sing-box` | `/etc/sing-box/config.json` | 9090, 1053 | `/usr/bin/sing-box` |
| **AdGuard Home** | `adguardhome` | `/var/lib/adguardhome/AdGuardHome.yaml` | 53, 8083 | `/usr/bin/adguardhome` |
| **Caddy 2** | `caddy` | `/etc/caddy/Caddyfile` | 80, 443 | `/usr/sbin/caddy` |
| **Vaultwarden** | `vaultwarden` | `/etc/conf.d/vaultwarden` | 8000 | `/usr/bin/vaultwarden` |
| **Forgejo Git** | `forgejo` | `/etc/forgejo/app.ini` | 3000, 22 | `/usr/bin/forgejo` |
| **qBittorrent** | `qbittorrent-nox` | `/var/lib/qbittorrent/.config/qBittorrent/` | 8080 | `/usr/bin/qbittorrent-nox` |
| **Navidrome** | `navidrome` | `/etc/navidrome.toml` | 4533 | `/usr/bin/navidrome` |
| **MeTube Web** | `ytdlp-web` | `/opt/homelab/scripts/ytdlp_web.py` | 8081 | Python 3 + `yt-dlp` |
| **Samba** | `samba` | `/etc/samba/smb.conf` | 445, 139 | `/usr/sbin/smbd` |
| **WSDD** | `wsdd` | `/etc/conf.d/wsdd` | 3702, 5357 | `/usr/bin/wsdd` |

## OpenRC & Capability Bounding Guidelines

1. **Privileged Ports (< 1024) Without Root:**
   - In `/etc/sysctl.d/99-gateway.conf`:
     ```ini
     net.ipv4.ip_unprivileged_port_start = 80
     ```
   - On Caddy binary:
     ```bash
     apk add libcap libcap-utils
     setcap cap_net_bind_service=+ep /usr/sbin/caddy
     ```
   - Pre-create log files with proper ownership:
     ```bash
     touch /var/log/caddy.log && chown caddy:caddy /var/log/caddy.log
     ```

2. **Caddy Local PKI (Internal CA without System Trust Mutation):**
   - In global Caddyfile block, always specify:
     ```caddy
     {
         admin off
         pki {
             ca local {
                 install_trust false
             }
         }
     }
     ```
   - This prevents unprivileged users from executing `tee` or modifying `/usr/local/share/ca-certificates`, eliminating startup errors.

3. **In-Place SQLite Optimizations:**
   - Ensure WAL mode and sync normal for Vaultwarden and Navidrome:
     `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;`
   - Store attachments and media on filesystem partitions with direct in-place allocation (ext4 or btrfs with `chattr +C`).

4. **Hot Backup Automations:**
   - **Vaultwarden:** Python `sqlite3.backup()` API ensures 100% zero-lock hot copies.
   - **Forgejo:** Run `su forgejo -s /bin/sh -c "forgejo dump --tempdir /tmp -f /tmp/dump.zip --config /etc/forgejo/app.ini"`. Ensure `/var/lib/forgejo/data/forgejo-repositories` exists.
   - **Navidrome:** Stream SQLite backup directly to gzip archive.
