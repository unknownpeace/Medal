---
name: appliance-qa-suite
description: >-
  Execute end-to-end testing, deep log audits, security sanitization, and automated verification
  for homelab gateway appliances. Use when testing endpoints, validating network modes
  (Gateway vs Router), diagnosing service crashes, inspecting logs, or preparing releases.
---

# Appliance QA & Verification Suite

Comprehensive testing procedures, automated scripts, and quality gates for verifying homelab gateway appliances and network infrastructure.

## Quality Gates & Verification Checklist

1. **Pre-flight & Deployment Smoke Test:**
   - Execute clean rollback of test VM / target partition.
   - Run installer in background, streaming output to log.
   - Ensure zero non-zero exit codes during package bootstrap and OpenRC service launches.

2. **Endpoint Health Checks (All 15 Target Services):**
   - Run [scripts/test_all_endpoints.py](./scripts/test_all_endpoints.py) against target host IP.
   - Verify HTTP 200 OK for:
     1. Portal: `http://<IP>/`
     2. AdGuard Home IP: `http://<IP>:8083`
     3. sing-box Clash UI: `http://<IP>:9090`
     4. qBittorrent WebUI: `http://<IP>:8080`
     5. Navidrome Music: `http://<IP>:4533`
     6. Forgejo Git: `http://<IP>:3000`
     7. MeTube Downloader: `http://<IP>:8081`
     8. Vaultwarden Passwords: `http://<IP>:8000`
     9. Local HTTPS Domains (`adguard.lan`, `proxy.lan`, `vault.lan`, `git.lan`, `torrent.lan`, `metube.lan`, `music.lan`)

3. **Network Mode Dynamic Transition Verification:**
   - Test Gateway Mode 1:
     - Verify `AdGuardHome.yaml` contains `dhcp: enabled: false`.
     - Confirm absence of DHCP socket conflicts with existing router.
   - Switch to Router Mode:
     - Execute `homelab mode router`.
     - Verify `AdGuardHome.yaml` contains `dhcp: enabled: true`.
     - Confirm exclusion of `.1` and `.5` in DHCP ranges.
     - Inspect nftables NAT table for forward and masquerade rules.
   - Switch back to Gateway Mode:
     - Execute `homelab mode gateway`.
     - Confirm clean atomic flush of nftables without dangling rules.

4. **Transparent Proxy & DNS Verification:**
   - Direct Russian resources: `curl -sI https://ya.ru` (must return 200/302 directly, low latency).
   - Filtered/Blocked resources: `curl -sI https://www.youtube.com` (must return HTTP/2 200 through PROXY tunnel).
   - DNS Resolution: `nslookup dl-cdn.alpinelinux.org 127.0.0.1` (must resolve only IPv4 A records, no AAAA leak or transient errors).

5. **Log Audit & Privacy Sanitization:**
   - Execute `homelab dump-logs`.
   - Ensure logs are fully sanitized: no JWT tokens, passwords, or proxy server credentials leaked.
