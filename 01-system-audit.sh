#!/bin/bash
# =============================================================================
# Debian 13 Server - Полный аудит системы
# =============================================================================
# Описание: Определение текущей конфигурации, создание бэкапов
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

# =============================================================================
# ФУНКЦИИ ЛОГИРОВАНИЯ
# =============================================================================
log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}\n${BLUE}►${NC} ${WHITE}$1${NC}\n${CYAN}═══════════════════════════════════════════════════${NC}\n"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Запустите с правами root: sudo ./01-system-audit.sh"
    exit 1
fi

# =============================================================================
# СОЗДАНИЕ ДИРЕКТОРИИ ДЛЯ БЭКАПОВ
# =============================================================================
BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/audit.log"

log_info "Создана директория для бэкапов: $BACKUP_DIR"

# =============================================================================
# ФУНКЦИЯ ЗАПИСИ В ЛОГ
# =============================================================================
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# =============================================================================
# РАЗДЕЛ 1: СБОР ИНФОРМАЦИИ О СИСТЕМЕ
# =============================================================================
log_step "Раздел 1: Сбор информации о системе"

# Информация о системе
echo "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ===" >> "$LOG_FILE"
hostnamectl >> "$LOG_FILE" 2>/dev/null || true
echo "" >> "$LOG_FILE"

echo "=== ВЕРСИЯ DEBIAN ===" >> "$LOG_FILE"
lsb_release -a >> "$LOG_FILE" 2>/dev/null || true
echo "" >> "$LOG_FILE"

echo "=== ЯДРО ===" >> "$LOG_FILE"
uname -a >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# =============================================================================
# РАЗДЕЛ 2: ОПРЕДЕЛЕНИЕ СЕТЕВЫХ НАСТРОЕК
# =============================================================================
log_step "Раздел 2: Определение сетевых настроек"

# Сетевые интерфейсы
echo "=== СЕТЕВЫЕ ИНТЕРФЕЙСЫ ===" >> "$LOG_FILE"
ip addr show >> "$LOG_FILE" 2>/dev/null || true
echo "" >> "$LOG_FILE"

# Определение основного интерфейса
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$MAIN_INTERFACE" ]; then
    MAIN_INTERFACE=$(ip link show | grep -E "^[0-9]+: e[n|t]" | head -1 | awk -F': ' '{print $2}')
fi
log_info "Основной сетевой интерфейс: $MAIN_INTERFACE"
echo "MAIN_INTERFACE=$MAIN_INTERFACE" >> "$LOG_FILE"

# IP-адреса
IPV4_ADDR=$(ip -4 addr show "$MAIN_INTERFACE" | grep inet | awk '{print $2}' | head -1)
IPV6_ADDR=$(ip -6 addr show "$MAIN_INTERFACE" | grep -v "fe80" | grep inet6 | awk '{print $2}' | head -1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)

log_info "IPv4: ${IPV4_ADDR:-не определен}"
log_info "IPv6: ${IPV6_ADDR:-не определен}"
log_info "Шлюз: ${GATEWAY:-не определен}"

echo "IPV4_ADDR=$IPV4_ADDR" >> "$LOG_FILE"
echo "IPV6_ADDR=$IPV6_ADDR" >> "$LOG_FILE"
echo "GATEWAY=$GATEWAY" >> "$LOG_FILE"

# Определение типа сетевой конфигурации
if [ -f /etc/network/interfaces ]; then
    NET_CONFIG_TYPE="interfaces"
    cp -v /etc/network/interfaces "$BACKUP_DIR/interfaces.backup" 2>/dev/null || true
    echo "=== /etc/network/interfaces ===" >> "$LOG_FILE"
    cat /etc/network/interfaces >> "$LOG_FILE" 2>/dev/null || true
elif [ -d /etc/systemd/network ]; then
    NET_CONFIG_TYPE="systemd-networkd"
    mkdir -p "$BACKUP_DIR/systemd-network"
    cp -rv /etc/systemd/network/* "$BACKUP_DIR/systemd-network/" 2>/dev/null || true
else
    NET_CONFIG_TYPE="unknown"
fi

log_info "Тип сетевой конфигурации: $NET_CONFIG_TYPE"
echo "NET_CONFIG_TYPE=$NET_CONFIG_TYPE" >> "$LOG_FILE"

# =============================================================================
# РАЗДЕЛ 3: ОПРЕДЕЛЕНИЕ SSH НАСТРОЕК
# =============================================================================
log_step "Раздел 3: Определение SSH настроек"

# Бэкап SSH конфигураций
mkdir -p "$BACKUP_DIR/ssh"

if [ -f /etc/ssh/sshd_config ]; then
    cp -v /etc/ssh/sshd_config "$BACKUP_DIR/ssh/sshd_config.backup" 2>/dev/null || true
    echo "=== /etc/ssh/sshd_config ===" >> "$LOG_FILE"
    cat /etc/ssh/sshd_config >> "$LOG_FILE" 2>/dev/null || true
fi

if [ -d /etc/ssh/sshd_config.d/ ]; then
    cp -rv /etc/ssh/sshd_config.d/* "$BACKUP_DIR/ssh/" 2>/dev/null || true
    echo "=== /etc/ssh/sshd_config.d/ ===" >> "$LOG_FILE"
    ls -la /etc/ssh/sshd_config.d/ >> "$LOG_FILE" 2>/dev/null || true
fi

# Определение текущего порта SSH
SSH_PORT=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
if [ -z "$SSH_PORT" ] && [ -d /etc/ssh/sshd_config.d/ ]; then
    SSH_PORT=$(grep -E "^Port\s+" /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | head -1)
fi
SSH_PORT=${SSH_PORT:-22}
log_info "Текущий порт SSH: $SSH_PORT"
echo "SSH_PORT=$SSH_PORT" >> "$LOG_FILE"

# =============================================================================
# РАЗДЕЛ 4: ОПРЕДЕЛЕНИЕ DNS НАСТРОЕК
# =============================================================================
log_step "Раздел 4: Определение DNS настроек"

# Бэкап resolv.conf
if [ -f /etc/resolv.conf ]; then
    cp -v /etc/resolv.conf "$BACKUP_DIR/resolv.conf.backup" 2>/dev/null || true
    echo "=== /etc/resolv.conf ===" >> "$LOG_FILE"
    cat /etc/resolv.conf >> "$LOG_FILE" 2>/dev/null || true
fi

# Проверка systemd-resolved
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    log_info "systemd-resolved активен"
    resolvectl status >> "$LOG_FILE" 2>/dev/null || true
    DNS_SERVICE="systemd-resolved"
else
    DNS_SERVICE="unknown"
fi
echo "DNS_SERVICE=$DNS_SERVICE" >> "$LOG_FILE"

# =============================================================================
# РАЗДЕЛ 5: ОПРЕДЕЛЕНИЕ NTP НАСТРОЕК
# =============================================================================
log_step "Раздел 5: Определение NTP настроек"

if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
    log_info "systemd-timesyncd активен"
    timedatectl status >> "$LOG_FILE" 2>/dev/null || true
    NTP_SERVICE="systemd-timesyncd"
elif systemctl is-active --quiet chrony 2>/dev/null; then
    NTP_SERVICE="chrony"
elif systemctl is-active --quiet ntp 2>/dev/null; then
    NTP_SERVICE="ntp"
else
    NTP_SERVICE="none"
fi
echo "NTP_SERVICE=$NTP_SERVICE" >> "$LOG_FILE"

# =============================================================================
# РАЗДЕЛ 6: ОПРЕДЕЛЕНИЕ ПОЛЬЗОВАТЕЛЕЙ
# =============================================================================
log_step "Раздел 6: Определение пользователей"

echo "=== ПОЛЬЗОВАТЕЛИ С sudo ПРАВАМИ ===" >> "$LOG_FILE"
getent group sudo | cut -d: -f4 >> "$LOG_FILE" 2>/dev/null || true
echo "" >> "$LOG_FILE"

# =============================================================================
# РАЗДЕЛ 7: СОЗДАНИЕ КОНФИГУРАЦИОННОГО ФАЙЛА
# =============================================================================
log_step "Раздел 7: Создание конфигурационного файла"

CONFIG_FILE="$BACKUP_DIR/system_config.conf"

cat > "$CONFIG_FILE" << EOF
# Конфигурация системы, определенная в процессе аудита
# Дата: $(date '+%Y-%m-%d %H:%M:%S')

# Сетевые настройки
MAIN_INTERFACE="$MAIN_INTERFACE"
IPV4_ADDR="$IPV4_ADDR"
IPV6_ADDR="$IPV6_ADDR"
GATEWAY="$GATEWAY"
NET_CONFIG_TYPE="$NET_CONFIG_TYPE"

# SSH настройки
SSH_PORT="$SSH_PORT"

# DNS настройки
DNS_SERVICE="$DNS_SERVICE"

# NTP настройки
NTP_SERVICE="$NTP_SERVICE"

# Путь к бэкапам
BACKUP_DIR="$BACKUP_DIR"
EOF

log_success "Конфигурационный файл создан: $CONFIG_FILE"

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Аудит системы завершен"

echo -e "${GREEN}✅${NC} Аудит системы завершен!"
echo ""
echo -e "${YELLOW}📋 Результаты аудита:${NC}"
echo "  Основной интерфейс: $MAIN_INTERFACE"
echo "  IPv4: ${IPV4_ADDR:-не определен}"
echo "  IPv6: ${IPV6_ADDR:-не определен}"
echo "  Шлюз: ${GATEWAY:-не определен}"
echo "  SSH порт: $SSH_PORT"
echo "  DNS служба: ${DNS_SERVICE:-не определена}"
echo "  NTP служба: ${NTP_SERVICE:-не определена}"
echo ""
echo -e "${CYAN}📁 Бэкапы сохранены в:${NC} $BACKUP_DIR"
echo ""
read -p "Нажмите Enter для продолжения..."
