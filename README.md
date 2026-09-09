# server-setup
Набор адаптивных скриптов для полной настройки сервера Debian 13.
# Debian 13 Server Setup — Полная настройка сервера

![Debian](https://img.shields.io/badge/Debian-13-red)
![Bash](https://img.shields.io/badge/Bash-5.2-green)

Набор адаптивных скриптов для полной настройки сервера Debian 13 (Trixie).

## 🔥 Что включено

### Базовая настройка
- ✅ Обновление системы
- ✅ Установка пакетов: unattended-upgrades, apt-listchanges, sudo, ufw, curl, git, mc, fail2ban, htop, nload, net-tools
- ✅ Настройка автоматических обновлений безопасности
- ✅ Настройка репозиториев (contrib, non-free, non-free-firmware)

### Сеть и DNS
- ✅ Настройка systemd-networkd (адаптивно)
- ✅ Настройка статического IP
- ✅ Настройка DNS через systemd-resolved (Google DNS + Cloudflare)
- ✅ Проверка сети и DNS

### Синхронизация времени (NTP)
- ✅ Настройка systemd-timesyncd
- ✅ Российские NTP серверы
- ✅ Fallback NTP серверы

### SSH и безопасность
- ✅ Создание нового пользователя
- ✅ Настройка SSH ключей (ввод или генерация)
- ✅ Смена порта SSH
- ✅ Отключение root login
- ✅ Отключение аутентификации по паролю
- ✅ Настройка UFW (фаервол)
- ✅ Настройка fail2ban (защита от брутфорса)

### Системные настройки
- ✅ Настройка hostname
- ✅ Создание SWAP файла
- ✅ Настройка локалей (ru_RU.UTF-8, en_US.UTF-8)
- ✅ Установка часового пояса (Asia/Yekaterinburg)
- ✅ Настройка ротации логов (800MB, 2 недели)

### Дополнительные сервисы (опционально)
- ✅ Docker + Docker Compose
- ✅ NetBird (VPN)
- ✅ Nginx Proxy Manager

## 📋 Скрипты

| Файл | Описание |
|------|----------|
| `01-system-audit.sh` | Аудит системы, определение конфигурации, создание бэкапов |
| `02-initial-setup.sh` | Обновление, установка пакетов, автоматические обновления |
| `03-network-dns-ntp.sh` | Настройка сети, DNS, NTP |
| `04-ssh-security.sh` | Настройка SSH, UFW, fail2ban, системные настройки |
| `05-install-services.sh` | Установка Docker, NetBird, NPM |

## 🚀 Быстрый старт

```bash
# 1. Клонирование
git clone https://github.com/yourusername/debian13-server-setup.git
cd debian13-server-setup

# 2. Права на выполнение
chmod +x *.sh

# 3. Последовательный запуск
sudo ./01-system-audit.sh          # Аудит и бэкапы
sudo ./02-initial-setup.sh         # Базовые пакеты
sudo ./03-network-dns-ntp.sh       # Сеть, DNS, NTP
sudo ./04-ssh-security.sh          # SSH, UFW, fail2ban
sudo ./05-install-services.sh      # Docker, NetBird, NPM


🔍 Как работают скрипты
1. Аудит (01-system-audit.sh)

    Определяет сетевые интерфейсы, IP, шлюз

    Находит порт SSH

    Определяет используемые службы DNS и NTP

    Создает бэкапы всех конфигураций

2. Базовая настройка (02-initial-setup.sh)

    Обновляет систему

    Устанавливает все необходимые пакеты

    Настраивает unattended-upgrades

    Настраивает репозитории

    Устанавливает hostname

3. Сеть, DNS, NTP (03-network-dns-ntp.sh)

    Настраивает systemd-networkd

    Настраивает DNS через systemd-resolved

    Настраивает NTP синхронизацию

    Проверяет работу

4. SSH и безопасность (04-ssh-security.sh)

    Создает пользователя

    Настраивает SSH ключи

    Меняет порт SSH

    Настраивает UFW

    Настраивает fail2ban

    Системные настройки (SWAP, локали, логи)

5. Сервисы (05-install-services.sh)

    Интерактивный выбор

    Docker, NetBird, NPM

📁 Бэкапы

Все бэкапы сохраняются в:
text

/root/backup_YYYYMMDD_HHMMSS/
├── system_config.conf
├── interfaces.backup
├── ssh/
├── resolv.conf.backup
├── hosts.backup
└── ...

⚠️ Важные замечания

    Все скрипты должны запускаться от root

    Перед запуском сделайте снапшот VPS

    Проверяйте новое SSH подключение перед закрытием старого

    Порт 22 оставляется открытым до подтверждения работы нового порта

📝 Пример подключения после настройки
bash

ssh -p 27244 vasa@<IP_АДРЕС>

🛠️ Устранение проблем
Восстановление доступа к SSH
bash

# Через консоль VPS
ufw allow 22/tcp
systemctl restart ssh

Проверка статуса
bash

systemctl status ssh ufw fail2ban docker
ufw status verbose
fail2ban-client status sshd

📄 Лицензия

MIT License
text


---

Теперь у вас есть **ПОЛНЫЙ** набор скриптов, включающий ВСЕ настройки из ваших файлов:

1. ✅ **Unattended-upgrades** — автоматические обновления
2. ✅ **Все пакеты** — sudo, ufw, curl, git, mc, fail2ban, htop, nload, net-tools
3. ✅ **Репозитории** — contrib, non-free, non-free-firmware
4. ✅ **Сеть** — systemd-networkd с определением интерфейсов
5. ✅ **DNS** — systemd-resolved с Google DNS + Cloudflare
6. ✅ **NTP** — systemd-timesyncd с российскими серверами
7. ✅ **SSH** — смена порта, отключение root, ключи, отключение паролей
8. ✅ **UFW** — настройка фаервола
9. ✅ **fail2ban** — защита от брутфорса
10. ✅ **SWAP** — создание swap файла
11. ✅ **Локали** — ru_RU.UTF-8
12. ✅ **Часовой пояс** — Asia/Yekaterinburg
13. ✅ **Ротация логов** — 800MB, 2 недели
14. ✅ **Hostname** — настройка имени хоста

Все скрипты адаптивные, с бэкапами и проверками!
