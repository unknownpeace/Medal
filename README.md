# 🛡️ Homelab Appliance & Transparent Gateway (Russia Pro Edition)

> **Автономный отказоустойчивый сервер и умный сетевой шлюз для дома и офиса.**
> 
> Разворачивает современный прозрачный шлюз с маршрутизацией заблокированных ресурсов на уровне роутера, блокировкой рекламы, безопасным парольным менеджером, Git-репозиторием, торрент-клиентом, медиа-загрузчиком, просмотрщиком логов, системой мониторинга и автоматическим самовосстановлением.

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
        AGH["🛡️ AdGuard Home (Порт 53)\nБлокировка рекламы + DNS-over-HTTPS/TLS"]
        MIHOMO["🚀 Mihomo Smart Core (TUN / Fake-IP 1053)\nРоутинг: YouTube, Discord, Telegram, AI"]
        CADDY["🔒 Caddy Reverse Proxy (HTTPS 443)\nInternal CA / DuckDNS Wildcard TLS"]

        subgraph STACK[" Docker Compose Stack (Autoheal & Healthchecks) "]
            VW["🔑 Vaultwarden (vault.lan)"]
            GIT["🐙 Gitea (git.lan)"]
            QBIT["📥 qBittorrent + VueTorrent (torrent.lan)"]
            METUBE["🎬 MeTube yt-dlp (metube.lan)"]
            LOGS["📋 Dozzle Web Logs (logs.lan)\n[Basic Auth]"]
            KUMA["📊 Uptime Kuma (status.lan)"]
            SMB["📂 Samba Storage (SMB3)"]
            HEAL["🩺 Autoheal Daemon"]
            WT["🔄 Watchtower Daemon"]
        end
    end

    subgraph WAN[" Внешняя сеть / Интернет "]
        RU_NET["🇷🇺 Российские ресурсы (Госуслуги, Банки, VK, Кинопоиск)\n100% ПРЯМОЙ ДОСТУП (DIRECT)"]
        BLOCKED_NET["🌐 YouTube, Discord, AI, Заблокированные сайты\nШИФРОВАННЫЙ ТУННЕЛЬ (PROXY)"]
        TG_API["📢 Telegram Bot Alerts API"]
    end

    PC & Phone & TV -->|DNS-запросы (UDP/TCP 53)| AGH
    PC & Phone & TV -->|TCP/UDP трафик| NFT

    AGH -->|Upstream DNS 1053| MIHOMO
    NFT -->|Smart Routing| MIHOMO

    MIHOMO -->|Правила DIRECT (.ru / GEOIP)| RU_NET
    MIHOMO -->|Правила PROXY (YouTube / AI / Discord)| BLOCKED_NET

    PC & Phone -->|HTTPS 443| CADDY
    CADDY --> VW & GIT & QBIT & METUBE & LOGS & KUMA

    HEAL -.->|Мониторинг здоровья| STACK
    NFT -.->|Алерты при сбоях| TG_API
```

---

## ⚡ Ключевые технологические особенности

1. **Встроенный обход DPI (TLS ClientHello Fragmentation)**
   - Нативная десинхронизация пакетов прямо в ядре Mihomo (`DIRECT-DPI`).
   - Фрагментация первого пакета TLS ClientHello (`size: 1-3`, `sleep: 2-5`), обходящая блокировки ТСПУ РКН для **YouTube** и **Discord** без использования зарубежных VPN и прокси, на полной скорости домашнего провайдера (100–1000 Мбит/с).

2. **Фаервол нового поколения: Native `nftables` + DNS Hijacking + TCP MSS Clamping**
   - Полный отказ от устаревшего `iptables` в пользу таблицы `table inet homelab`.
   - **DNS Hijacking (Anti-Bypass):** Принудительный перехват всех DNS-запросов (порт 53 UDP/TCP) от «упрямых» устройств (Smart TV, Android, Chromecast, малварь с хардкодом `8.8.8.8`) и их перенаправление в AdGuard Home.
   - **TCP MSS Clamping (`tcp option maxseg size set rt mtu`):** Автоматическая подгонка размера сегмента TCP под MTU исходящего интерфейса, исключающая «зависания» сайтов и медленную загрузку страниц на PPPoE/L2TP/VPN-соединениях.
   - Защита от петель маршрутизации (anti-looping filter), изоляция управляющих портов AdGuard (8083) и Mihomo (9090) от внешней сети.
   - Атомарное применение правил и автосохранение (`/etc/nftables.d/homelab.nft`).

3. **Оптимизированные правила Mihomo (Russia Pro Edition)**
   - Компактные бинарные наборы правил MRS (`meta-rules-dat`).
   - Дедуплицированные правила: полное исключение избыточных доменов `.ru`, `.рф`, `.su`, защищённых через `DOMAIN-SUFFIX`.
   - Выделенные прокси-группы: `YouTube`, `Discord`, `Telegram`, `AI-Services` (ChatGPT, Claude, Gemini, Copilot), `DIRECT`, `AUTO`.
   - Нулевая капча и отсутствие геоблоков на Госуслугах, сайтах банков, Озоне, WB, Кинопоиске.

4. **Интеллектуальный Watchdog 2.0 и Самовосстановление (Self-Healing)**
   - Фоновый сторожевой таймер с активными L7-пробами: регулярная проверка резолвинга DNS через AdGuard Home (`dig/nslookup @127.0.0.1 -p 53`) и отзывчивости API Mihomo (порт 9090).
   - Автоматический перезапуск зависших сервисов, перепрошивка сетевых правил и отправка тревожных уведомлений в Telegram.
   - Демон `autoheal` непрерывно следит за состоянием всех Docker-контейнеров стека.

5. **Глобальная ротация логов Docker (Защита от переполнения диска)**
   - Глобальная конфигурация `/etc/docker/daemon.json` (`json-file`, `max-size: 10m`, `max-file: 3`).
   - Дублирующая защита на уровне `compose.yaml` для каждого сервиса — гарантирует, что логи контейнеров никогда не забьют диск сервера.

6. **Защищённый просмотр логов: Dozzle Web UI**
   - Легковесный интерфейс просмотра журналов работы всех контейнеров в реальном времени (`https://logs.lan`).
   - Потребление памяти всего ~10 МБ.
   - Защита через HTTP Basic Auth с единым мастер-паролем администратора.

7. **Мониторинг доступности: Uptime Kuma**
   - Дашборд состояния сервисов и внешних ресурсов (`https://status.lan`).
   - Автоматический горячий бэкап базы данных SQLite с оптимизацией Btrfs No-COW.

8. **Система Telegram-оповещений**
   - Мгновенные уведомления о сбоях маршрутизации, падении контейнеров и успешном завершении ночного резервного копирования баз данных.

9. **Единая консольная утилита: `homelab CLI`**
   - Управление всем комплексом из одного места: `homelab status`, `homelab doctor`, `homelab logs`, `homelab dump-logs`, `homelab restart`, `homelab backup`, `homelab notify`, `homelab update`.

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
| **Uptime Kuma** | `https://status.lan` | Мониторинг доступности и аптайма сервисов | Задается при первом входе |
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
- **2) Расширенная настройка:** Выбор отдельных сервисов, настройка дисковых разделов (Btrfs No-COW, LUKS2 шифрование), привязка DuckDNS и Telegram-бота.
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
  backup              Мгновенное создание горячего бэкапа SQLite баз (Vaultwarden, Gitea, Kuma)
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

- **Btrfs No-COW:** Все базы данных (SQLite в Vaultwarden, Gitea, AdGuard Home, Uptime Kuma) создаются с атрибутом `+C` (No Copy-on-Write) для предотвращения фрагментации и максимальной скорости дискового ввода-вывода.
- **Шифрование LUKS2:** Поддержка полного шифрования диска с хранилищем при физическом доступе.
- **Сертификаты:** Автоматический выпуск корневого CA сертификата (`caddy-root.crt`), доступного в шаре Samba для простой установки на телефоны и ПК.

---

## 📄 Лицензия

Распространяется под лицензией MIT. Подробности в файле [LICENSE](LICENSE).
