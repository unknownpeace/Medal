#!/usr/bin/env python3
"""
Appliance Endpoint Testing Suite
Tests all 15 endpoints (HTTP Portal, IP:Port direct services, and *.lan HTTPS domains).
"""
import sys
import ssl
import urllib.request
import socket

def test_endpoint(name, url, host_header=None, ip=None, timeout=5):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    req_url = url
    if host_header and ip:
        req_url = url.replace(host_header, ip)
    
    req = urllib.request.Request(req_url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Host": host_header if host_header else urllib.parse.urlsplit(url).netloc.split(':')[0]
    } if host_header else {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})

    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            code = resp.getcode()
            ctype = resp.headers.get("Content-Type", "")
            return True, f"HTTP {code} ({ctype})"
    except urllib.error.HTTPError as e:
        return True, f"HTTP {e.code} (Response received)"
    except Exception as e:
        return False, f"ERROR: {e}"

def main():
    target_ip = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.147"
    print(f"[*] Testing Appliance Endpoints on {target_ip}...\n")
    
    tests = [
        ("Portal (Root HTTP)", f"http://{target_ip}/", None),
        ("AdGuard Home (IP:8083)", f"http://{target_ip}:8083/", None),
        ("sing-box UI (IP:9090)", f"http://{target_ip}:9090/", None),
        ("qBittorrent (IP:8080)", f"http://{target_ip}:8080/", None),
        ("Navidrome (IP:4533)", f"http://{target_ip}:4533/", None),
        ("Forgejo Git (IP:3000)", f"http://{target_ip}:3000/", None),
        ("MeTube (IP:8081)", f"http://{target_ip}:8081/", None),
        ("Vaultwarden (IP:8000)", f"http://{target_ip}:8000/", None),
        ("AdGuard (adguard.lan)", f"https://adguard.lan/", "adguard.lan"),
        ("sing-box (proxy.lan)", f"https://proxy.lan/", "proxy.lan"),
        ("Vaultwarden (vault.lan)", f"https://vault.lan/", "vault.lan"),
        ("Forgejo (git.lan)", f"https://git.lan/", "git.lan"),
        ("qBittorrent (torrent.lan)", f"https://torrent.lan/", "torrent.lan"),
        ("MeTube (metube.lan)", f"https://metube.lan/", "metube.lan"),
        ("Navidrome (music.lan)", f"https://music.lan/", "music.lan"),
    ]

    passed = 0
    total = len(tests)

    for name, url, host in tests:
        ok, msg = test_endpoint(name, url, host_header=host, ip=target_ip)
        status_icon = "✔" if ok else "✖"
        print(f"  {status_icon} {name:<26} -> {msg}")
        if ok:
            passed += 1

    print(f"\n[*] Result: {passed}/{total} endpoints passed.")
    sys.exit(0 if passed == total else 1)

if __name__ == "__main__":
    import urllib.parse
    main()
