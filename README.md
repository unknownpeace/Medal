# 🛡️ Homelab Appliance & Transparent Gateway (Russia Pro Edition)

> **Автономный отказоустойчивый сервер и умный сетевой шлюз для дома и офиса.**
> 
> Разворачивает современный прозрачный шлюз с маршрутизацией заблокированных ресурсов на уровне роутера, блокировкой рекламы, безопасным парольным менеджером, Git-репозиторием, торрент-клиентом, медиа-загрузчиком, просмотрщиком логов в реальном времени и автоматическим самовосстановлением.

[![Linux](https://img.shields.io/badge/OS-Alpine%20|%20Debian%20|%20Ubuntu%20|%20Arch-blue.svg)](https://kernel.org)
[![Firewall](https://img.shields.io/badge/Firewall-Native%20nftables-green.svg)](https://netfilter.org/projects/nftables/)
[![Docker](https://img.shields.io/badge/Docker-Self--Healing%20Autoheal-2496ED.svg)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

---

## 🏗️ Архитектура системы

Комплекс работает по принципу **Transparent Gateway (Прозрачный шлюз)**. Вы указываете IP-адрес сервера в DHCP-настройках домашнего роутера как шлюз (Gateway) и DNS, после чего **все устройства в сети** (ПК, смартфоны, Smart TV, консоли) автоматически получают фильтрацию рекламы и доступ к заблокированным ресурсам без установки клиентских приложений.

```mermaid
flowchart TD
    subgraph LAN[" Домашняя сеть / Клиентские устройства "]
        PC["💻 Компьютер"]
        Phone["📱 Смартфон / Планшет"]
        TV["📺 Smart TV / Консоль"]
    end

    subgraph GW[" Homelab Server (Прозрачный шлюз) "]
        NFT["⚡ nftables (inet homelab)\nЗащита от петель + NAT Masquerade"]
        AGH["🛡️ AdGuard Home (Порт 53)\nБлокировка рекламы + Device Discovery\n(Zero-Cache для Fake-IP синхронизации)"]
        MIHOMO["🚀 Mihomo Smart Core (TUN / Fake-IP 1053)\nРоутинг: YouTube, Discord, Telegram, AI"]
        CADDY["🔒 Caddy Reverse Proxy (HTTPS 443)\nInternal CA / DuckDNS Wildcard TLS"]

        subgraph STACK[" Docker Compose Stack (Autoheal & Healthchecks) "]
            VW["🔑 Vaultwarden (vault.lan)"]
            GIT["🐙 Gitea (git.lan)"]
            QBIT["📥 qBittorrent + VueTorrent (torrent.lan)"]
            METUBE["🎬 MeTube yt-dlp (metube.lan)"]
            LOGS["📋 Dozzle Web Logs (logs.lan)\n[Basic Auth]"]
            SMB["📂 Samba Storage (SMB3)"]
            HEAL["🩺 Autoheal Daemon"]
            WT["🔄 Watchtower Daemon"]
        end
    end

    subgraph WAN[" Внешняя сеть / Интернет "]
        RU_NET["🇷🇺 Российские ресурсы (Госуслуги, Банки, VK, Кинопоиск)\n100% ПРЯМОЙ ДОСТУП (DIRECT)"]
        BLOCKED_NET["🌐 YouTube, Discord, AI, Заблокированные сайты\nШИФРОВАННЫЙ ТУННЕЛЬ (PROXY / AUTO)"]
        TG_API["📢 Telegram Bot Alerts API"]
    end

    PC & Phone & TV -->|DNS-запросы (UDP/TCP 53)| AGH
    PC & Phone & TV -->|TCP/UDP трафик| NFT

    AGH -->|Upstream DNS 1053| MIHOMO
    NFT -->|Smart Routing| MIHOMO

    MIHOMO -->|Правила DIRECT (.ru / GEOIP)| RU_NET
    MIHOMO -->|Правила PROXY / AUTO (YouTube / AI / Discord)| BLOCKED_NET

    PC & Phone -->|HTTPS 443| CADDY
    CADDY --> VW & GIT & QBIT & METUBE & LOGS

    HEAL -.->|Мониторинг здоровья| STACK
    NFT -.->|Алерты при сбоях| TG_API
```

---

## ⚡ Ключевые технологические особенности

1. **Умная маршрутизация трафика (Smart Proxy Tunneling)**
   - Разделение трафика на уровне ядра Mihomo: российские ресурсы (`*.ru`, `.рф`, `.su`, Госуслуги, банки, маркетплейсы, VK) направляются на 100% напрямую (`DIRECT`), сохраняя максимальную скорость провайдера (до 1 Гбит/с) и избавляя от капчи и геоблокировок.
   - Популярные заблокированные сервисы (**YouTube**, **Discord**, **Telegram**, **AI-сервисы** — ChatGPT, Claude, Gemini, Copilot) и реестр заблокированных ресурсов автоматически направляются через активные прокси-туннели (`AUTO` с автоматическим тестированием задержки url-test или ручной выбор `PROXY`).

2. **Фаервол нового поколения: 100% Native `nftables` + DNS Hijacking + TCP MSS Clamping**
   - Полный отказ от устаревшего `iptables` в пользу чистой архитектуры `table inet homelab`. Ноль устаревших зависимостей.
   - **DNS Hijacking (Anti-Bypass):** Принудительный перехват всех DNS-запросов (порт 53 UDP/TCP) от устройств с жестко прописанными DNS (Smart TV, Android, Chromecast, IoT) и их бесшовное перенаправление в AdGuard Home.
   - **TCP MSS Clamping (`tcp option maxseg size set rt mtu`):** Автоматическая адаптация максимального размера сегмента TCP под MTU исходящего интерфейса — устраняет зависания сайтов и долгую загрузку страниц на PPPoE/L2TP/VPN-подключениях.
   - Защита от петель маршрутизации (anti-looping filter), изоляция сервисных портов AdGuard (8083) и Mihomo (9090) от внешней сети.
   - Атомарное применение правил и сохранение (`/etc/nftables.d/homelab.nft`).

3. **Синхронизация AdGuard Home & Mihomo Fake-IP (Zero-Cache & Device Discovery)**
   - AdGuard Home выступает первым эшелоном DNS-фильтрации (порт 53), очищая запросы от трекеров и рекламы, а вышестоящим апстримом выступает Fake-IP DNS Mihomo (порт 1053).
   - **Zero DNS Cache:** Кэш в AdGuard Home намеренно отключен (`cache_size: 0`, `cache_optimistic: false`). Это полностью исключает рассинхронизацию Fake-IP пула Mihomo, гарантируя, что связка домена и временного IP всегда актуальна при переходах и перезапусках ядра.
   - **Деанонимизация клиентов и Device Discovery:** Анонимизация IP отключена (`anonymize_client_ip: false`), включены локальные PTR-запросы к роутеру и сканирование ARP/DHCP — в панели AdGuard Home отображаются настоящие имена и IP-адреса каждого домашнего устройства.
   - Mihomo оптимизирован для работы в роли прозрачного шлюза: `store-fake-ip: true`, алгоритм кэширования `cache-algorithm: arc`, нативный TUN-интерфейс `device: Meta`.

4. **Оптимизированные правила Mihomo (Russia Pro Edition)**
   - Компактные бинарные наборы правил MRS (`meta-rules-dat`).
   - Дедуплицированные правила: домены зон `.ru`, `.рф`, `.su` отсекаются по правилу `DOMAIN-SUFFIX`, минимизируя размер базы правил и нагрузку на процессор.
   - Выделенные прокси-группы: `YouTube`, `Discord`, `Telegram`, `AI-Services`, `DIRECT`, `AUTO`, `PROXY`.

5. **Интеллектуальный Watchdog 2.0 и Самовосстановление (Self-Healing)**
   - Фоновый сторожевой таймер с активными L7-пробами: регулярная проверка резолвинга DNS через AdGuard Home (`dig/nslookup @127.0.0.1 -p 53`) и отзывчивости API Mihomo (порт 9090).
   - Автоматический перезапуск зависших сервисов, перепрошивка сетевых правил и отправка тревожных уведомлений в Telegram.
   - Демон `autoheal` непрерывно следит за состоянием всех Docker-контейнеров стека.

6. **Глобальная ротация логов Docker (Защита от переполнения диска)**
   - Глобальная конфигурация `/etc/docker/daemon.json` (`json-file`, `max-size: 10m`, `max-file: 3`).
   - Дублирующая защита на уровне `compose.yaml` для каждого сервиса — логи контейнеров гарантированно не переполнят накопитель сервера.

7. **Защищённый просмотр логов: Dozzle Web UI**
   - Легковесный интерфейс просмотра журналов работы всех контейнеров в реальном времени (`https://logs.lan`).
   - Потребление памяти всего ~12 МБ (написан на Go).
   - Защита через HTTP Basic Auth с единым мастер-паролем администратора.
   - Отсутствие тяжелых избыточных служб мониторинга позволяет серверу работать плавно даже на системах с 1 ГБ RAM.

8. **Система Telegram-оповещений**
   - Мгновенные уведомления о сбоях маршрутизации, падении контейнеров и успешном завершении ночного резервного копирования баз данных.

9. **Единая консольная утилита: `homelab CLI`**
   - Управление всем комплексом из одного места: `homelab status`, `homelab doctor`, `homelab logs`, `homelab dump-logs`, `homelab restart`, `homelab backup`, `homelab notify`, `homelab update`.

10. **Сохранение конфигурации и удобство повторного запуска**
    - Все введённые при установке параметры (URL подписки, шлюз, интерфейсы, пароли, токены) автоматически сохраняются в `/opt/homelab/.env`.
    - При повторном запуске скрипта для обновления или перенастройки вам не нужно вводить всё заново — достаточно нажимать [Enter] для подтверждения сохранённых значений.

---

## 🌐 Каталог веб-сервисов

| Сервис | Локальный домен | Назначение | Авторизация |
| :--- | :--- | :--- | :--- |
| **AdGuard Home** | `https://adguard.lan` | DNS-сервер, блокировка рекламы, родительский контроль | `admin` / Мастер-пароль |
| **Mihomo UI** | `https://proxy.lan` | Веб-панель переключения прокси и режимов маршрутизации | Секрет (Мастер-пароль) |
| **Vaultwarden** | `https://vault.lan` | Менеджер паролей (Bitwarden-совместимый) | Собственная + `/admin` токен |
| **Gitea** | `https://git.lan` | Персональный Git-сервер (SSH порт 2222) | `admin` / Мастер-пароль |
| **qBittorrent** | `https://torrent.lan` | Торрент-клиент с премиальным UI VueTorrent | `admin` / Мастер-пароль |
| **MeTube** | `https://metube.lan` | Скачивание видео/аудио с YouTube и 100+ сайтов | Без пароля (LAN) |
| **Dozzle** | `https://logs.lan` | Просмотр логов контейнеров в реальном времени | `admin` / Мастер-пароль |
| **Samba (SMB3)** | `\\<IP-сервера>\storage` | Сетевая папка для Windows, macOS, Android TV | `admin` / Мастер-пароль |

*(При выборе SSL-режима DuckDNS домены имеют вид `*.ваш-домен.duckdns.org`)*

---

## 🚀 Быстрый старт и установка

### Системные требования
- **ОС:** Alpine Linux v3.19+, Debian 12/13, Ubuntu 24.04/26.04 LTS, Arch Linux.
- **Архитектура:** `x86_64` (amd64) или `aarch64` (ARM64 / Raspberry Pi / Orange Pi).
- **ОЗУ:** от 1 ГБ (автоматически настраивается zram-swap со сжатием zstd).
- **Права:** `root` (или запуск через `sudo`).

### Запуск установки

Склонируйте репозиторий и запустите скрипт:

```bash
git clone https://github.com/your-username/homelab.git
cd homelab
chmod +x install.sh
sudo ./install.sh
```

Или в одну команду:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/your-username/homelab/main/install.sh)"
```

### Режимы установки
- **1) Экспресс-установка (Zero-Touch):** Все сервисы включаются автоматически, генерируется надёжный единый пароль, разворачивается локальный PKI CA.
- **2) Расширенная настройка:** Выбор отдельных сервисов, умная настройка хранилища (адаптивный Btrfs No-COW, LUKS2 шифрование), привязка DuckDNS и Telegram-бота.
- **3) Сброс стека (--reset):** Полная и чистая деинсталляция всех компонентов без следов в системе.

---

## 🛠️ Консольная утилита `homelab`

После установки вам доступна глобальная утилита `/usr/local/bin/homelab`:

```text
Использование: homelab [КОМАНДА] [ОПЦИИ]

Команды:
  status              Вывести дашборд состояния системы, ОЗУ, дисков и контейнеров
  doctor              Глубокая самодиагностика DNS (53), Mihomo (1053), TUN, nftables
  restart [сервис]    Перезапустить весь комплекс или отдельный контейнер
  stop [сервис]       Остановить комплекс или контейнер
  start [сервис]      Запустить сервисы комплекса
  logs [сервис] -f    Просмотр журналов логов в терминале в реальном времени
  backup              Мгновенное создание горячего бэкапа SQLite баз (Vaultwarden, Gitea)
  notify [сообщение]  Отправить тестовое оповещение в Telegram
  update              Безопасное обновление всех Docker-образов стека
  unlock              Ручная разблокировка шифрованного диска LUKS2
  help                Показать справку
```

### Примеры:
```bash
# Проверить здоровье всех сервисов
homelab status

# Запустить самодиагностику сетевого шлюза
homelab doctor

# Посмотреть живые логи Caddy или Mihomo
homelab logs caddy -f
homelab logs mihomo -f

# Сделать резервную копию прямо сейчас
homelab backup
```

---

## 📱 Настройка роутера (1 действие для всей квартиры)

После завершения установки в панели управления вашего домашнего роутера (Keenetic, MikroTik, ASUS, TP-Link, OpenWrt):

1. Откройте раздел **DHCP / Локальная сеть**.
2. Укажите в поле **Основной шлюз (Gateway):** `IP-адрес вашего Homelab-сервера`.
3. Укажите в поле **DNS-сервер:** `IP-адрес вашего Homelab-сервера`.
4. Сохраните и перезагрузите роутер (или переподключите Wi-Fi на устройствах).

*Теперь все устройства пользуются чистым, быстрым интернетом без рекламы и блокировок!*

---

## 🔒 Безопасность и хранение данных

- **Адаптивная оптимизация хранилища (Btrfs No-COW / ext4 / xfs):** Скрипт автоматически определяет файловую систему целевого диска. Если используется Btrfs, на каталоги баз данных (SQLite в Vaultwarden, Gitea, AdGuard Home) и директорию торрентов qBittorrent автоматически выставляется флаг `+C` (No Copy-on-Write) для предотвращения фрагментации и максимальной скорости ввода-вывода. Для дисков на `ext4`/`xfs` применяются оптимальные стандартные POSIX-параметры без ошибок `chattr`.
- **Шифрование LUKS2:** Поддержка полного шифрования диска с хранилищем при физическом доступе.
- **Сертификаты:** Автоматический выпуск корневого CA сертификата (`caddy-root.crt`), доступного в шаре Samba для простой установки на телефоны и ПК.

---

## 📄 Лицензия

Распространяется под лицензией MIT. Подробности в файле [LICENSE](LICENSE).
