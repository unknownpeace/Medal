#!/usr/bin/env bash
# ==============================================================================
# BUNDLER / COMPILER FOR HOMELAB INSTALLER
# Собирает модули из src/*.sh в единый монолитный install.sh для однострочной установки
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
OUTPUT_FILE="${SCRIPT_DIR}/install.sh"

echo "==> Сборка монолитного установщика install.sh из модулей ${SRC_DIR}..."

MODULES=(
    "00_header.sh"
    "01_system.sh"
    "02_packages.sh"
    "03_network.sh"
    "04_config.sh"
    "05_gateway.sh"
    "05b_zapret.sh"
    "06_directories.sh"
    "07_dns_bench.sh"
    "08_services_conf.sh"
    "09_compose_caddy.sh"
    "10_backups_cli.sh"
    "11_diagnostics.sh"
)

# Проверка наличия всех модулей
for mod in "${MODULES[@]}"; do
    if [ ! -f "${SRC_DIR}/${mod}" ]; then
        echo "[-] Ошибка: модуль ${SRC_DIR}/${mod} не найден!" >&2
        exit 1
    fi
done

# Инициализация выходного файла первым модулем
cat "${SRC_DIR}/00_header.sh" > "${OUTPUT_FILE}"

# Конкатенация остальных модулей с удалением дублирующих shebang
for mod in "${MODULES[@]:1}"; do
    echo "" >> "${OUTPUT_FILE}"
    sed -e '1{/^#!\/usr\/bin\/env bash/d; /^#!\/bin\/bash/d; /^#!\/bin\/sh/d;}' "${SRC_DIR}/${mod}" >> "${OUTPUT_FILE}"
done

chmod +x "${OUTPUT_FILE}" 2>/dev/null || true

TOTAL_LINES=$(wc -l < "${OUTPUT_FILE}" 2>/dev/null || echo "N/A")
echo "[+] Сборка завершена успешно: ${OUTPUT_FILE} (${TOTAL_LINES} строк)"
