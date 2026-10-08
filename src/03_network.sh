# =============================================================================
# Module: 03_network.sh
# Network Environment Analysis & Disk Safety Management
# =============================================================================

detect_network() {
    print_step_header "02/11" "ИНТЕЛЛЕКТУАЛЬНЫЙ АНАЛИЗ СЕТЕВОГО ОКРУЖЕНИЯ"

    if [ -n "${SAVED_PHYS_IFACE:-}" ] && ip link show dev "${SAVED_PHYS_IFACE}" >/dev/null 2>&1; then
        DEFAULT_IFACE="${SAVED_PHYS_IFACE}"
    else
        PHYS_IFACE=$( (ip -o -4 route show default 2>/dev/null | awk '{print $5}' | grep -vE '^(Meta|tun|tap|docker|br-|veth|wg|tailscale|zt|dummy|bond|lo)' | head -n1) || true )
        if [ -z "${PHYS_IFACE}" ]; then
            PHYS_IFACE=$( (ip -o -4 addr show scope global 2>/dev/null | awk '{print $2}' | grep -vE '^(Meta|tun|tap|docker|br-|veth|wg|tailscale|zt|dummy|bond|lo)' | head -n1) || true )
        fi
        if [ -z "${PHYS_IFACE}" ]; then
            PHYS_IFACE=$(ls -1 /sys/class/net 2>/dev/null | grep -E '^(eth|en|wl)' | head -n1 || true)
        fi
        DEFAULT_IFACE="${PHYS_IFACE:-eth0}"
    fi

    LOCAL_IP=$(ip -o -4 addr show dev "${DEFAULT_IFACE}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
    if [ -z "${LOCAL_IP}" ] || [ "${LOCAL_IP}" = "127.0.0.1" ]; then
        LOCAL_IP=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i !~ /^127\./) {print $i; exit}}')
        LOCAL_IP=${LOCAL_IP:-192.168.1.100}
    fi

    ROUTER_GATEWAY=$(ip route show default dev "${DEFAULT_IFACE}" 2>/dev/null | awk '/via/ {for(j=1;j<=NF;j++) if($j=="via") {print $(j+1); exit}}' | head -n1 || true)
    if [ -z "${ROUTER_GATEWAY}" ] || [ "${ROUTER_GATEWAY}" = "${LOCAL_IP}" ] || [[ ! "${ROUTER_GATEWAY}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ROUTER_GATEWAY=$(ip neigh show dev "${DEFAULT_IFACE}" 2>/dev/null | grep -E 'REACHABLE|DELAY|STALE' | awk '{print $1}' | grep -v "${LOCAL_IP}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)
    fi
    if [ -z "${ROUTER_GATEWAY}" ] || [[ ! "${ROUTER_GATEWAY}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ROUTER_GATEWAY=$(echo "${LOCAL_IP}" | sed 's/\.[0-9]*$/.1/' || echo "192.168.1.1")
    fi

    RAW_SUBNET=$(ip -o -f inet addr show dev "${DEFAULT_IFACE}" 2>/dev/null | awk '{print $4}' | head -n1 || true)
    if [ -n "${RAW_SUBNET}" ]; then
        LAN_SUBNET=$(python3 -c "import ipaddress; print(ipaddress.ip_network('${RAW_SUBNET}', strict=False))" 2>/dev/null || echo "${RAW_SUBNET}")
    else
        LAN_SUBNET="192.168.1.0/24"
    fi

    REAL_USER="${SUDO_USER:-$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || echo "homelab")}"
    TARGET_USER="${SAVED_TARGET_USER:-${REAL_USER:-homelab}}"
    if ! id -u "${TARGET_USER}" >/dev/null 2>&1; then
        useradd -m -U -s /bin/bash "${TARGET_USER}" 2>/dev/null || \
        useradd -m -s /bin/bash "${TARGET_USER}" 2>/dev/null || \
        adduser -D -s /bin/bash "${TARGET_USER}" 2>/dev/null || true
    fi
    USER_UID=$(id -u "${TARGET_USER}")
    USER_GID=$(id -g "${TARGET_USER}")

    getent group docker >/dev/null 2>&1 || grep -q '^docker:' /etc/group 2>/dev/null || groupadd -r docker 2>/dev/null || addgroup -S docker 2>/dev/null || true
    usermod -aG docker "${TARGET_USER}" 2>/dev/null || adduser "${TARGET_USER}" docker 2>/dev/null || addgroup "${TARGET_USER}" docker 2>/dev/null || true
    if [ -S /var/run/docker.sock ]; then
        chown root:docker /var/run/docker.sock 2>/dev/null || true
        chmod 660 /var/run/docker.sock 2>/dev/null || true
    fi

    log_ok "Сетевые параметры определены:"
    echo -e "      ${CLR_WHITE}• ОС и ядро:        ${PRETTY_NAME:-Linux} ($(uname -r)) [Init: ${INIT_SYSTEM}]${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Архитектура:      ${SYSTEM_ARCH} (Аппаратный AES: $([ $HAS_HARDWARE_AES -eq 1 ] && echo "Да" || echo "Нет"))${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• IP сервера:       ${CLR_GREEN}${LOCAL_IP}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Шлюз роутера:     ${CLR_CYAN}${ROUTER_GATEWAY}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Интерфейс LAN:    ${CLR_YELLOW}${DEFAULT_IFACE}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Подсеть LAN:      ${LAN_SUBNET}${CLR_RESET}"
    echo -e "      ${CLR_WHITE}• Пользователь:     ${TARGET_USER} (UID: ${USER_UID}, GID: ${USER_GID})${CLR_RESET}"
}

get_disk_parent() {
    local dev="$1"
    python3 -c "
import sys, os, subprocess, re
dev = os.path.realpath(sys.argv[1])
try:
    res = subprocess.check_output(['lsblk', '-slno', 'NAME,TYPE', dev], stderr=subprocess.DEVNULL).decode().strip()
    if res:
        for line in reversed(res.splitlines()):
            parts = line.split()
            if len(parts) >= 2 and parts[1] == 'disk':
                print(parts[0])
                sys.exit(0)
except Exception:
    pass
name = os.path.basename(dev)
if 'nvme' in name or 'mmcblk' in name:
    print(re.sub(r'p\d+$', '', name))
else:
    print(re.sub(r'\d+$', '', name))
" "${dev}" 2>/dev/null || basename "${dev}"
}

release_device() {
    local dev="$1"
    [ -z "$dev" ] && return 0
    local real_dev
    real_dev=$(readlink -f "$dev" 2>/dev/null || echo "$dev")

    log_info "Освобождение накопителя ${dev} от блокировок ядра и файловых систем..."

    if mountpoint -q "${MOUNT_ROOT}"; then
        fuser -km "${MOUNT_ROOT}" 2>/dev/null || true
        umount -R "${MOUNT_ROOT}" 2>/dev/null || umount -l "${MOUNT_ROOT}" 2>/dev/null || true
    fi

    while read -r mnt; do
        if [ -n "$mnt" ] && [ "$mnt" != "/" ] && [[ ! "$mnt" =~ ^/(boot|efi|usr|var|home) ]]; then
            fuser -km "$mnt" 2>/dev/null || true
            umount -R "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
        fi
    done < <(lsblk -rno MOUNTPOINT "${real_dev}" 2>/dev/null | grep -v '^$' || true)

    while read -r crypt_holder; do
        if [ -n "$crypt_holder" ]; then
            cryptsetup close "$crypt_holder" 2>/dev/null || dmsetup remove -f "$crypt_holder" 2>/dev/null || true
        fi
    done < <(lsblk -lno NAME,TYPE "${real_dev}" 2>/dev/null | awk '$2=="crypt" {print $1}')
    cryptsetup close "${LUKS_MAP_NAME}" 2>/dev/null || dmsetup remove -f "${LUKS_MAP_NAME}" 2>/dev/null || true

    swapoff "${real_dev}"* 2>/dev/null || true
    blockdev --flushbufs "${real_dev}" 2>/dev/null || true
    udevadm settle 2>/dev/null || sleep 1

    log_info "Очистка сигнатур разметки (wipefs)..."
    for part in $(lsblk -lno PATH "${real_dev}" 2>/dev/null | tail -n +2); do
        wipefs -af "${part}" 2>/dev/null || true
    done
    if ! wipefs -af "${real_dev}" 2>/dev/null; then
        dd if=/dev/zero of="${real_dev}" bs=1M count=16 oflag=direct status=none 2>/dev/null || \
        dd if=/dev/zero of="${real_dev}" bs=1M count=16 status=none 2>/dev/null || true
        blockdev --rereadpt "${real_dev}" 2>/dev/null || true
        udevadm settle 2>/dev/null || sleep 1
        wipefs -af "${real_dev}" 2>/dev/null || true
    fi
}

assert_safe_device() {
    local target_dev="$1"
    local real_target
    real_target=$(readlink -f "${target_dev}" 2>/dev/null || echo "${target_dev}")
    local target_disk
    target_disk=$(get_disk_parent "${real_target}")

    local root_src
    root_src=$(findmnt -n -o SOURCE / 2>/dev/null || df -P / 2>/dev/null | awk 'NR==2 {print $1}')
    root_src="${root_src%%[*}"
    local root_disk
    root_disk=$(get_disk_parent "${root_src}")

    if [ -n "${root_disk}" ] && [ "${target_disk}" = "${root_disk}" ]; then
        echo ""
        log_err "КРИТИЧЕСКАЯ БЛОКИРОВКА БЕЗОПАСНОСТИ!"
        log_err "Устройство ${target_dev} является системным накопителем (/dev/${root_disk}) текущей ОС!"
        log_err "Форматирование системного диска категорически запрещено."
        echo -e "      ${CLR_YELLOW}Для хранения на системном диске выберите режим [1] (Системный диск).${CLR_RESET}"
        exit 1
    fi

    local sys_mounts
    sys_mounts=$(lsblk -lno MOUNTPOINT "${real_target}" 2>/dev/null | grep -E '^/(boot|efi|usr|var|home)($|/)' || true)
    if [ -n "${sys_mounts}" ]; then
        echo ""
        log_err "КРИТИЧЕСКАЯ БЛОКИРОВКА БЕЗОПАСНОСТИ!"
        log_err "Накопитель ${target_dev} содержит системные разделы ОС:"
        echo -e "      ${CLR_YELLOW}${sys_mounts}${CLR_RESET}"
        log_err "Форматирование диска с системными компонентами запрещено."
        exit 1
    fi

    local cur_mounts
    cur_mounts=$(lsblk -lno MOUNTPOINT "${real_target}" 2>/dev/null | grep -E '^/(mnt|media)' || true)
    if [ -n "${cur_mounts}" ]; then
        log_info "Освобождение диска: отмонтирование разделов хранилища..."
        while read -r mnt_pt; do
            [ -n "$mnt_pt" ] && (umount -R "$mnt_pt" 2>/dev/null || umount -l "$mnt_pt" 2>/dev/null || true)
        done <<< "${cur_mounts}"
        cryptsetup close "${LUKS_MAP_NAME}" 2>/dev/null || true
    fi
}

select_disk_device() {
    log_info "Сканирование доступных физических накопителей..."

    local ROOT_SRC
    ROOT_SRC=$(findmnt -n -o SOURCE / 2>/dev/null || df -P / 2>/dev/null | awk 'NR==2 {print $1}')
    ROOT_SRC="${ROOT_SRC%%[*}"
    local ROOT_DISK
    ROOT_DISK=$(get_disk_parent "${ROOT_SRC}")

    local SYSTEM_DISKS=()
    [ -n "${ROOT_DISK}" ] && SYSTEM_DISKS+=("${ROOT_DISK}")

    for smpt in /boot /boot/efi /efi /usr /var /home; do
        if [ -d "$smpt" ]; then
            local s_src
            s_src=$(findmnt -n -o SOURCE "$smpt" 2>/dev/null || true)
            s_src="${s_src%%[*}"
            if [ -n "$s_src" ]; then
                local s_disk
                s_disk=$(get_disk_parent "$s_src")
                [ -n "$s_disk" ] && SYSTEM_DISKS+=("${s_disk}")
            fi
        fi
    done

    while read -r sw_dev rest; do
        [ -z "$sw_dev" ] || [ "$sw_dev" = "Filename" ] && continue
        local sw_disk
        sw_disk=$(get_disk_parent "$sw_dev")
        [ -n "$sw_disk" ] && SYSTEM_DISKS+=("${sw_disk}")
    done < /proc/swaps 2>/dev/null || true

    AVAIL_DEVS=()
    while read -r d_name d_type; do
        [ "$d_type" != "disk" ] && continue
        [ -z "$d_name" ] && continue
        [[ "$d_name" =~ ^(loop|zram|ram) ]] && continue
        [[ "$d_name" =~ (boot[0-9]|rpmb)$ ]] && continue

        local is_system=0
        for sys_d in "${SYSTEM_DISKS[@]}"; do
            if [ "$d_name" = "$sys_d" ]; then
                is_system=1
                break
            fi
        done
        [ "$is_system" -eq 1 ] && continue

        AVAIL_DEVS+=("/dev/${d_name}")
    done < <(lsblk -dno NAME,TYPE 2>/dev/null || true)

    if [ ${#AVAIL_DEVS[@]} -eq 0 ]; then
        echo ""
        log_err "Свободные внешние/дополнительные накопители не найдены!"
        echo -e "      ${CLR_WHITE}Системный диск /dev/${ROOT_DISK:-sda} исключен из списка безопасности.${CLR_RESET}"
        echo -e "      ${CLR_YELLOW}Подключите внешний диск или выберите режим [1] (Хранилище на системном диске).${CLR_RESET}"
        exit 1
    fi

    echo ""
    echo -e "  ${CLR_CYAN}Доступные дополнительные/внешние накопители (системный диск /dev/${ROOT_DISK:-sda} исключен):${CLR_RESET}"
    for i in "${!AVAIL_DEVS[@]}"; do
        local DEV_NAME="${AVAIL_DEVS[$i]}"
        local DEV_INFO
        DEV_INFO=$(lsblk -dno SIZE,MODEL,TRAN "${DEV_NAME}" 2>/dev/null | xargs)
        local ROTATIONAL
        ROTATIONAL=$(cat "/sys/block/$(basename "$DEV_NAME")/queue/rotational" 2>/dev/null || echo "1")
        local MEDIA_TYPE="HDD"
        [ "$ROTATIONAL" = "0" ] && MEDIA_TYPE="SSD/NVMe"
        printf "    ${CLR_WHITE}%d)${CLR_RESET} %-18s ${CLR_YELLOW}[%s | %s]${CLR_RESET}\n" "$((i+1))" "${DEV_NAME}" "${MEDIA_TYPE}" "${DEV_INFO:-Без метки}"
    done
    echo ""

    prompt_read "  [?] Выберите номер диска [1-${#AVAIL_DEVS[@]}]: " DEV_IDX
    while [[ ! "${DEV_IDX:-}" =~ ^[0-9]+$ ]] || [ "${DEV_IDX}" -lt 1 ] || [ "${DEV_IDX}" -gt "${#AVAIL_DEVS[@]}" ]; do
        prompt_read "  [-] Неверный выбор. Введите номер из списка: " DEV_IDX
    done

    CHOSEN_DEV="${AVAIL_DEVS[$((DEV_IDX-1))]}"
    assert_safe_device "${CHOSEN_DEV}"
    log_ok "Выбрано целевое устройство: ${CHOSEN_DEV}"
}
