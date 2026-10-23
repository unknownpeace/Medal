# Realtek RTL8812BU / 88x2bu Wi-Fi AP & Router Mode Reference

## Hardware & Driver Details
- **USB Vendor/Product:** `0bda:b812` (Realtek USB3.0 802.11ac 1200M Adapter)
- **Kernel Module:** `rtw88_8822bu` (in-tree Linux 6.2+)
- **Required Packages on Alpine Linux:**
  - `linux-firmware-rtw88`: Provides `rtw88/rtw8822b_fw.bin` (Firmware version 30.20.0, H2C version 14)
  - `wireless-regdb`: Provides `regulatory.db` to prevent `cfg80211: failed to load regulatory.db` errors
  - `iw`, `wireless-tools`

## Hostapd Configuration (802.11ac 5GHz or 802.11n 2.4GHz)
File: `/etc/hostapd/hostapd.conf`
```ini
interface=wlan0
driver=nl80211
ssid=Homelab_5G
country_code=RU
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
vht_oper_chwidth=0
vht_oper_centr_freq_seg0_idx=36
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_passphrase=YourSecretPassword
rsn_pairwise=CCMP
```

## Router Mode Activation Steps
1. Bring up wireless device: `ip link set dev wlan0 up`
2. Assign static IP gateway: `ip addr add 192.168.1.147/24 dev wlan0`
3. Activate AdGuard Home DHCP on `wlan0`:
   - Set `dhcp.enabled: true` and `interface_name: "wlan0"` in `AdGuardHome.yaml`.
   - Reload AdGuard Home: `rc-service adguardhome restart`
4. Apply 2-NIC NAT forwarding in nftables.
