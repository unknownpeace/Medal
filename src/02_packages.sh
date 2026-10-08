# =============================================================================
# Module: 02_packages.sh
# System Package Installation (Alpine, Arch, Debian, Ubuntu), Docker CE, zRAM
# =============================================================================

install_pkgs() {
    print_step_header "01/11" "УСТАНОВКА ЗАВИСИМОСТЕЙ И СТЕКА DOCKER"

    if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ] && command -v docker >/dev/null 2>&1 && command -v nft >/dev/null 2>&1; then
        log_ok "Системные зависимости и Docker CE уже установлены (пропуск в режиме обновления)"
        return 0
    fi

    if [ "${DISTRO_FAMILY}" = "alpine" ]; then
        if [ -f /etc/apk/repositories ]; then
            sed -i 's/^#\(.*\/community\)/\1/' /etc/apk/repositories 2>/dev/null || true
            if ! grep -q '/community' /etc/apk/repositories 2>/dev/null; then
                awk '{print} /\/main$/ {sub(/\/main$/, "/community"); print}' /etc/apk/repositories > /etc/apk/repositories.tmp 2>/dev/null && \
                mv /etc/apk/repositories.tmp /etc/apk/repositories 2>/dev/null || true
            fi
        fi
        run_spin "Обновление индексов пакетов APK" apk update

        local ALP_PKGS=(bash python3 py3-bcrypt iproute2 cryptsetup btrfs-progs ntfs-3g \
                        util-linux util-linux-misc lsblk curl openssl ca-certificates jq nftables apache2-utils \
                        unzip tar sqlite argon2 iputils shadow procps e2fsprogs ffmpeg \
                        docker docker-cli-compose chrony openrc)
        run_spin "Установка системных пакетов Alpine" \
            apk add --no-cache "${ALP_PKGS[@]}"
        apk add --no-cache cryptsetup-openrc >/dev/null 2>&1 || true

    elif [ "${DISTRO_FAMILY}" = "arch" ]; then
        local ARCH_PKGS=(python python-bcrypt iproute2 cryptsetup btrfs-progs ntfs-3g util-linux \
                         curl openssl ca-certificates jq nftables unzip tar sqlite ffmpeg \
                         docker docker-compose argon2 iputils acl zram-generator)
        local MISSING_PKGS=()
        for p in "${ARCH_PKGS[@]}"; do
            pacman -Q "$p" >/dev/null 2>&1 || MISSING_PKGS+=("$p")
        done
        if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
            log_ok "Все системные пакеты Arch Linux уже установлены (пропуск)"
        else
            run_spin "Установка пакетов Arch (${#MISSING_PKGS[@]} шт.)" \
                pacman -S --noconfirm --needed "${MISSING_PKGS[@]}"
        fi
    elif [ "${DISTRO_FAMILY}" = "debian" ]; then
        export DEBIAN_FRONTEND=noninteractive
        run_spin "Обновление индексов пакетов APT" bash -c "apt-get update -o Acquire::Check-Valid-Until=false -y || apt-get update -y"

        local ZRAM_PKG="systemd-zram-generator"
        if [[ "${OS_ID}" =~ ubuntu ]] || [[ "${OS_ID_LIKE}" =~ ubuntu ]]; then
            ZRAM_PKG="zram-generator"
        fi

        run_spin "Установка системных пакетов и утилит" \
            apt-get install -y --no-install-recommends \
                systemd-timesyncd python3 python3-bcrypt iproute2 cryptsetup btrfs-progs ntfs-3g \
                util-linux curl openssl ca-certificates jq nftables apache2-utils \
                unzip tar sqlite3 argon2 iputils-ping ffmpeg

        # Установка генератора zram с безопасным fallback для Ubuntu/Debian
        apt-get install -y --no-install-recommends "${ZRAM_PKG}" 2>/dev/null || \
        apt-get install -y --no-install-recommends zram-tools 2>/dev/null || true

        if ! command -v docker >/dev/null 2>&1; then
            log_info "Установка официального Docker CE..."
            apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true

            local REPO_OS="debian"
            [[ "${OS_ID}" =~ ubuntu ]] || [[ "${OS_ID_LIKE}" =~ ubuntu ]] && REPO_OS="ubuntu"
            local CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
            if [ -z "${CODENAME}" ]; then
                [ "${REPO_OS}" = "ubuntu" ] && CODENAME="resolute" || CODENAME="trixie"
            fi

            install -m 0755 -d /etc/apt/keyrings
            if ! curl -fsSL --connect-timeout 5 -m 12 "https://download.docker.com/linux/${REPO_OS}/gpg" -o /etc/apt/keyrings/docker.asc 2>/dev/null; then
                log_warn "download.docker.com недоступен. Загрузка GPG-ключа с официального зеркала mirror.yandex.ru..."
                curl -fsSL --connect-timeout 5 -m 12 "https://mirror.yandex.ru/mirrors/docker-ce/linux/${REPO_OS}/gpg" -o /etc/apt/keyrings/docker.asc
            fi
            chmod a+r /etc/apt/keyrings/docker.asc

            local DOCKER_REPO_URL="https://download.docker.com/linux/${REPO_OS}"
            if ! curl -fsSL --connect-timeout 4 -m 8 "https://download.docker.com/linux/${REPO_OS}/" -o /dev/null 2>/dev/null; then
                DOCKER_REPO_URL="https://mirror.yandex.ru/mirrors/docker-ce/linux/${REPO_OS}"
                log_info "Используется высокоскоростное зеркало Docker CE в РФ: ${DOCKER_REPO_URL}"
            fi

            local TARGET_CODENAME="${CODENAME}"
            if ! curl -fsSL --connect-timeout 5 -m 10 "${DOCKER_REPO_URL}/dists/${TARGET_CODENAME}/Release" -o /dev/null 2>/dev/null && \
               ! curl -fsSL --connect-timeout 5 -m 10 "${DOCKER_REPO_URL}/dists/${TARGET_CODENAME}/InRelease" -o /dev/null 2>/dev/null; then
                [ "${REPO_OS}" = "ubuntu" ] && TARGET_CODENAME="noble" || TARGET_CODENAME="bookworm"
                log_warn "Репозиторий для ${CODENAME} недоступен. Используется совместимый: ${TARGET_CODENAME}"
            fi

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_REPO_URL} ${TARGET_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
            
            run_spin "Обновление репозиториев с Docker CE" apt-get update -y
            run_spin "Установка компонентов Docker CE и Compose Plugin" \
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi
    fi

    # Защита накопителя eMMC/SSD: ограничение системного журнала systemd-journald
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        mkdir -p /etc/systemd/journald.conf.d/
        cat <<EOF_JRNL > /etc/systemd/journald.conf.d/00-homelab.conf
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
Storage=persistent
EOF_JRNL
        systemctl restart systemd-journald >/dev/null 2>&1 || true
    fi

    # Настройка актуальных зеркал Docker Hub (2026 год, устойчивость к блокировкам в РФ)
    local MODIFIED_DAEMON
    MODIFIED_DAEMON=$(python3 -c "
import json, os
path = '/etc/docker/daemon.json'
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
mirrors = data.get('registry-mirrors', [])
target_mirrors = [
    'https://dockerhub.timeweb.cloud',
    'https://dockerproxy.net',
    'https://docker.m.daocloud.io'
]
changed = False
for bad in ['https://huecker.io', 'https://mirror.gcr.io', 'https://dockerhub.cloud.ru']:
    while bad in mirrors:
        mirrors.remove(bad)
        changed = True
# Гарантируем, что проверенные зеркала находятся первыми в списке
new_mirrors = []
for tm in target_mirrors:
    new_mirrors.append(tm)
for m in mirrors:
    if m not in new_mirrors:
        new_mirrors.append(m)
if new_mirrors != mirrors:
    mirrors = new_mirrors
    changed = True

if 'log-driver' not in data:
    data['log-driver'] = 'json-file'
    data['log-opts'] = {'max-size': '10m', 'max-file': '3'}
    changed = True
if data.get('max-concurrent-downloads') != 3:
    data['max-concurrent-downloads'] = 3
    data['max-concurrent-uploads'] = 2
    changed = True
if changed:
    os.makedirs('/etc/docker', exist_ok=True)
    data['registry-mirrors'] = mirrors
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print('1')
else:
    print('0')
" 2>/dev/null || echo "0")

    if [ "${INIT_SYSTEM}" = "openrc" ]; then
        rc-update add cgroups boot >/dev/null 2>&1 || true
        rc-service cgroups start >/dev/null 2>&1 || true
        rc-update add docker default >/dev/null 2>&1 || true
        if ! rc-service docker status >/dev/null 2>&1; then
            run_spin "Активация и запуск службы Docker (OpenRC)" rc-service docker start
        elif [ "${MODIFIED_DAEMON}" = "1" ]; then
            run_spin "Обновление конфигурации и перезапуск Docker (актуализированы зеркала)" rc-service docker restart
        else
            log_ok "Служба Docker активна, зеркала Docker Hub уже настроены"
        fi
    else
        if ! systemctl is-active --quiet docker 2>/dev/null; then
            run_spin "Активация и запуск службы Docker" bash -c "systemctl daemon-reload >/dev/null 2>&1 || true && systemctl enable --now docker >/dev/null 2>&1 || true"
        elif [ "${MODIFIED_DAEMON}" = "1" ]; then
            run_spin "Обновление конфигурации и перезапуск Docker (актуализированы зеркала)" bash -c "systemctl daemon-reload >/dev/null 2>&1 || true && systemctl restart docker"
        else
            log_ok "Служба Docker активна, зеркала Docker Hub уже настроены"
        fi
    fi

    if command -v docker >/dev/null 2>&1; then
        docker stop mihomo adguardhome 2>/dev/null || true
    fi

    DETECTED_DOCKER_API=$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || echo "1.45")
    if [ -z "${DETECTED_DOCKER_API}" ]; then
        DETECTED_DOCKER_API="1.45"
    else
        DETECTED_DOCKER_API=$(python3 -c "
import sys
api = '${DETECTED_DOCKER_API}'
try:
    major, minor = [int(x) for x in api.split('.')[:2]]
    if major > 1 or (major == 1 and minor > 45):
        print('1.45')
    elif major == 1 and minor < 40:
        print('1.40')
    else:
        print(f'{major}.{minor}')
except Exception:
    print('1.45')
" 2>/dev/null || echo "1.45")
    fi
    log_info "Согласована стабильная версия Docker API: ${DETECTED_DOCKER_API}"

    mkdir -p /usr/lib/docker/cli-plugins /usr/libexec/docker/cli-plugins
    if command -v docker-compose >/dev/null 2>&1; then
        local DC_PATH
        DC_PATH=$(command -v docker-compose)
        [ ! -e /usr/lib/docker/cli-plugins/docker-compose ] && ln -sf "${DC_PATH}" /usr/lib/docker/cli-plugins/docker-compose
        [ ! -e /usr/libexec/docker/cli-plugins/docker-compose ] && ln -sf "${DC_PATH}" /usr/libexec/docker/cli-plugins/docker-compose
    fi

    local DC_BIN_TMP="/usr/local/bin/dc.tmp.$$"
    cat << 'EOF_DC_BIN' > "${DC_BIN_TMP}"
#!/usr/bin/env bash
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    exec docker compose "$@"
elif command -v docker-compose >/dev/null 2>&1; then
    exec docker-compose "$@"
elif [ -x /usr/lib/docker/cli-plugins/docker-compose ]; then
    exec /usr/lib/docker/cli-plugins/docker-compose "$@"
elif [ -x /usr/libexec/docker/cli-plugins/docker-compose ]; then
    exec /usr/libexec/docker/cli-plugins/docker-compose "$@"
else
    exec docker compose "$@"
fi
EOF_DC_BIN
    chmod 755 "${DC_BIN_TMP}" 2>/dev/null || true
    mv -f "${DC_BIN_TMP}" /usr/local/bin/dc 2>/dev/null || true

    log_ok "Стек Docker CE успешно настроен и готов к работе"
}

setup_zram() {
    if [ "${IS_UPGRADE_MODE:-0}" -eq 1 ] && (swapon --show 2>/dev/null | grep -q 'zram' || [ -f /etc/systemd/zram-generator.conf ] || [ -f /etc/init.d/zram-swap ]); then
        log_ok "Конфигурация zRAM уже активна (пропуск в режиме обновления)"
        return 0
    fi
    local TOTAL_RAM_MB
    TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "2048")
    if [ "${TOTAL_RAM_MB}" -le 4096 ]; then
        log_info "Обнаружен компактный объем RAM (${TOTAL_RAM_MB} МБ). Настройка zRAM..."
        if [ "${INIT_SYSTEM}" = "systemd" ]; then
            mkdir -p /etc/systemd/
            cat << 'EOF_ZRAM_CONF' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = min(ram / 2, 2048)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF_ZRAM_CONF

            if systemctl list-unit-files 2>/dev/null | grep -q "systemd-zram-setup"; then
                systemctl daemon-reload >/dev/null 2>&1 || true
                systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || \
                systemctl start dev-zram0.swap 2>/dev/null || systemctl start /dev/zram0 2>/dev/null || true
            fi
        elif [ "${INIT_SYSTEM}" = "openrc" ]; then
            cat << 'EOF_ZRAM_RC' > /etc/init.d/zram-swap
#!/sbin/openrc-run
description="zRAM Swap Activation"
depend() {
    after localmount
}
start() {
    ebegin "Activating zRAM swap"
    modprobe zram 2>/dev/null || true
    if command -v zramctl >/dev/null 2>&1; then
        ZDEV=$(zramctl --find --size 1024M --algorithm zstd 2>/dev/null || zramctl --find --size 1024M 2>/dev/null || true)
        if [ -n "${ZDEV}" ]; then
            mkswap "${ZDEV}" >/dev/null 2>&1
            swapon -p 100 "${ZDEV}" >/dev/null 2>&1
            sysctl -w vm.swappiness=150 >/dev/null 2>&1 || true
        fi
    fi
    eend 0
}
stop() {
    ebegin "Deactivating zRAM swap"
    for zd in $(lsblk -lno NAME,TYPE 2>/dev/null | awk '$2=="zram"{print "/dev/"$1}'); do
        swapoff "$zd" 2>/dev/null || true
        zramctl -r "$zd" 2>/dev/null || true
    done
    eend 0
}
EOF_ZRAM_RC
            chmod 755 /etc/init.d/zram-swap
            rc-update add zram-swap default >/dev/null 2>&1 || true
        fi

        if ! swapon --show 2>/dev/null | grep -q "zram"; then
            modprobe zram 2>/dev/null || true
            if command -v zramctl >/dev/null 2>&1; then
                local ZDEV
                ZDEV=$(zramctl --find --size 1024M --algorithm zstd 2>/dev/null || zramctl --find --size 1024M 2>/dev/null || true)
                if [ -n "${ZDEV}" ]; then
                    mkswap "${ZDEV}" >/dev/null 2>&1 || true
                    swapon -p 100 "${ZDEV}" 2>/dev/null || true
                    sysctl -w vm.swappiness=150 >/dev/null 2>&1 || true
                    log_ok "zRAM диск успешно активирован: ${ZDEV} (1 ГБ сжатия zstd)"
                fi
            fi
        else
            log_ok "zRAM активен и сконфигурирован"
        fi
    fi

    local TOTAL_SWAP_MB
    TOTAL_SWAP_MB=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}' || echo "0")
    if [ "${TOTAL_SWAP_MB:-0}" -lt 1024 ] && [ "${TOTAL_RAM_MB}" -le 3072 ]; then
        local AVAIL_DISK_MB
        AVAIL_DISK_MB=$(df -m / 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
        if [ ! -s /swapfile ] && [ "${AVAIL_DISK_MB}" -ge 3000 ]; then
            log_info "Создание дополнительного файла подкачки (1.5 ГБ Swapfile) для защиты от OOM..."
            local ROOT_FSTYPE
            ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || df -T / 2>/dev/null | awk 'NR==2{print $2}' || echo "ext4")

            if [ "${ROOT_FSTYPE}" = "btrfs" ] && command -v btrfs >/dev/null 2>&1; then
                btrfs filesystem mkswapfile --size 1536M /swapfile 2>/dev/null || {
                    truncate -s 0 /swapfile
                    chattr +C /swapfile 2>/dev/null || true
                    btrfs property set /swapfile compression none 2>/dev/null || true
                    dd if=/dev/zero of=/swapfile bs=1M count=1536 status=none
                }
            else
                (fallocate -l 1536M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1536 status=none)
            fi

            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1 || true
            if swapon -p 50 /swapfile >/dev/null 2>&1; then
                if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
                    echo "/swapfile none swap defaults,pri=50 0 0" >> /etc/fstab
                fi
                log_ok "Аварийный Swapfile успешно подключен (/swapfile, 1.5 ГБ)"
            fi
        fi
    fi
}
