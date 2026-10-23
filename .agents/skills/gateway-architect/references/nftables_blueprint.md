# Canonical Gateway nftables Architecture (`table inet homelab`)

## Atomic Reload Pattern
Always flush the table before re-adding to eliminate duplicate rules:
```nftables
table inet homelab
delete table inet homelab

table inet homelab {
    chain forward {
        type filter hook forward priority -10; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
        accept
    }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "eth0" tcp dport 53 redirect to :53
        iifname "eth0" udp dport 53 redirect to :53
        iifname "eth0" tcp dport 853 reject with tcp reset
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "eth0" masquerade
        oifname "tun0" masquerade
    }

    chain input {
        type filter hook input priority filter; policy accept;
        ip saddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8 } tcp dport { 8083, 9090 } drop
    }
}
```

## Router Mode (2-NIC Forwarding & Input Drop on WAN):
```nftables
table inet homelab
delete table inet homelab

table inet homelab {
    chain forward {
        type filter hook forward priority -10; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
        iifname "wlan0" oifname "eth0" accept
        iifname "wlan0" oifname "tun0" accept
        ct state { established, related } accept
    }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "wlan0" tcp dport 53 redirect to :53
        iifname "wlan0" udp dport 53 redirect to :53
        iifname "wlan0" tcp dport 853 reject with tcp reset
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "eth0" masquerade
        oifname "tun0" masquerade
    }

    chain input {
        type filter hook input priority filter; policy accept;
        iifname "lo" accept
        ct state { established, related } accept
        iifname "wlan0" accept
        iifname "eth0" tcp dport { 22, 80, 443 } accept
        iifname "eth0" drop
    }
}
```
