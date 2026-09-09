#!/bin/bash
# =============================================================================
# Debian 13 Server - Настройка сети, DNS, NTP
# =============================================================================
# Описание: Настройка systemd-networkd, DNS, NTP
# Версия: 1.0
# =============================================================================

set -e
set -u

# =============================================================================
# ЦВЕТНОЙ ВЫВОД
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}\n${BLUE}►${NC} ${WHITE}$1${NC}\n${CYAN}═══════════════════════════════════════════════════${NC}\n"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Запустите с правами root: sudo ./03-network-dns-ntp.sh"
    exit 1
fi

# =============================================================================
# ЗАГРУЗКА КОНФИГУРАЦИИ
# =============================================================================
BACKUP_DIR=$(ls -td /root/backup_* 2>/dev/null | head -1)
if [ -z "$BACKUP_DIR" ]; then
    log_error "Не найдена директория с бэкапами"
    exit 1
fi

source "$BACKUP_DIR/system_config.conf" 2>/dev/null || true
LOG_FILE="$BACKUP_DIR/network_setup.log"

# =============================================================================
# РАЗДЕЛ 1: НАСТРОЙКА СЕТИ (systemd-networkd)
# =============================================================================
log_step "Раздел 1: Настройка сети (systemd-networkd)"

# Бэкап существующих конфигураций
if [ -f /etc/network/interfaces ]; then
    mv -v /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S) 2>&1 | tee -a "$LOG_FILE"
fi

# Включение systemd-networkd
systemctl enable systemd-networkd
systemctl start systemd-networkd

# Создание конфигурации
NETWORK_FILE="/etc/systemd/network/10-lan0.network"

cat > "$NETWORK_FILE" << EOF
[Match]
Name=$MAIN_INTERFACE

[Network]
# Настройки IPv4
Address=$IPV4_ADDR
Gateway=$GATEWAY
DNS=8.8.8.8 1.1.1.1 1.0.0.1
Domains=localdomain
EOF

# Добавление IPv6 если есть
if [ ! -z "$IPV6_ADDR" ]; then
    IPV6_GATEWAY=$(ip -6 route | grep default | awk '{print $3}' | head -1)
    if [ -z "$IPV6_GATEWAY" ]; then
        IPV6_NET=$(echo "$IPV6_ADDR" | cut -d'/' -f1 | cut -d':' -f1-4)
        IPV6_GATEWAY="${IPV6_NET}::1"
    fi
    
    cat >> "$NETWORK_FILE" << EOF

# Настройки IPv6
Address=$IPV6_ADDR
Gateway=$IPV6_GATEWAY
DNS=2001:4860:4860::8888 2606:4700:4700::1111 2606:4700:4700::1001
EOF
fi

log_success "Конфигурация создана: $NETWORK_FILE"
cat "$NETWORK_FILE"

# Применение
systemctl restart systemd-networkd
sleep 3

log_info "Проверка применения:"
ip addr show "$MAIN_INTERFACE" | grep -E "inet |inet6 "

# =============================================================================
# РАЗДЕЛ 2: НАСТРОЙКА DNS (systemd-resolved)
# =============================================================================
log_step "Раздел 2: Настройка DNS"

# Установка systemd-resolved
apt install -y systemd-resolved 2>&1 | tee -a "$LOG_FILE"

# Бэкап resolv.conf
if [ -f /etc/resolv.conf ]; then
    mv /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S) 2>&1 | tee -a "$LOG_FILE"
fi

# Временное добавление хостов для установки
echo "130.89.148.77 deb.debian.org" >> /etc/hosts
echo "146.75.118.132 cdn-fastly.deb.debian.org" >> /etc/hosts

# Конфигурация resolved
cat > /etc/systemd/resolved.conf << 'EOF'
[Resolve]
DNS=8.8.8.8 1.1.1.1
DNS=2001:4860:4860::8888 2606:4700:4700::1111
Domains=~.
Cache=yes
DNSStubListener=yes
EOF

# Включение службы
systemctl enable --now systemd-resolved

# Очистка временных записей
sed -i '/deb.debian.org/d' /etc/hosts
sed -i '/cdn-fastly.deb.debian.org/d' /etc/hosts

# Настройка resolv.conf
ln -sfv /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Перезапуск служб
systemctl restart dbus
systemctl restart systemd-networkd
systemctl restart systemd-resolved

# Очистка кэша DNS
resolvectl flush-caches

# Проверка
log_info "Проверка DNS..."
sleep 2
resolvectl status
resolvectl query google.com

# =============================================================================
# РАЗДЕЛ 3: НАСТРОЙКА NTP
# =============================================================================
log_step "Раздел 3: Настройка NTP"

# Установка systemd-timesyncd
apt install -y systemd-timesyncd 2>&1 | tee -a "$LOG_FILE"

# Конфигурация
cat > /etc/systemd/timesyncd.conf << 'EOF'
[Time]
NTP=0.ru.pool.ntp.org 1.ru.pool.ntp.org 2.ru.pool.ntp.org 3.ru.pool.ntp.org
FallbackNTP=cloudflare.com 0.pool.ntp.org 1.pool.ntp.org
RootDistanceMaxSec=5
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF

# Включение
systemctl enable --now systemd-timesyncd
timedatectl set-ntp true

sleep 3

log_info "Статус NTP:"
timedatectl status
timedatectl timesync-status

# =============================================================================
# РАЗДЕЛ 4: ПРОВЕРКА
# =============================================================================
log_step "Раздел 4: Финальная проверка"

echo -e "${YELLOW}Проверка сети:${NC}"
ping -c 3 8.8.8.8 && log_success "Доступ к интернету есть" || log_error "Нет доступа к интернету"

echo -e "\n${YELLOW}Проверка DNS:${NC}"
nslookup google.com && log_success "DNS работает" || log_error "DNS не работает"

echo -e "\n${YELLOW}Проверка NTP:${NC}"
timedatectl status | grep "System clock synchronized"

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Настройка сети, DNS, NTP завершена"

echo -e "${GREEN}✅${NC} Сеть, DNS, NTP настроены!"
echo ""
echo -e "${YELLOW}📋 Результаты:${NC}"
echo "  Интерфейс: $MAIN_INTERFACE"
echo "  IPv4: $IPV4_ADDR"
echo "  IPv6: ${IPV6_ADDR:-не настроен}"
echo "  DNS: 8.8.8.8, 1.1.1.1"
echo "  NTP: 0.ru.pool.ntp.org"
echo ""
echo -e "${CYAN}📁 Бэкапы:${NC} $BACKUP_DIR"
echo ""
read -p "Нажмите Enter для продолжения..."
