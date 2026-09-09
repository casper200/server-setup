#!/bin/bash
# =============================================================================
# Debian 13 Server - Базовая настройка системы
# =============================================================================
# Описание: Установка пакетов, настройка unattended-upgrades
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
    log_error "Запустите с правами root: sudo ./02-initial-setup.sh"
    exit 1
fi

# =============================================================================
# ЗАГРУЗКА КОНФИГУРАЦИИ
# =============================================================================
BACKUP_DIR=$(ls -td /root/backup_* 2>/dev/null | head -1)
if [ -z "$BACKUP_DIR" ]; then
    log_error "Не найдена директория с бэкапами. Сначала выполните 01-system-audit.sh"
    exit 1
fi

source "$BACKUP_DIR/system_config.conf" 2>/dev/null || true
LOG_FILE="$BACKUP_DIR/initial_setup.log"

# =============================================================================
# РАЗДЕЛ 1: ОБНОВЛЕНИЕ СИСТЕМЫ
# =============================================================================
log_step "Раздел 1: Обновление системы"

log_info "Обновление списка пакетов..."
apt update 2>&1 | tee -a "$LOG_FILE"

log_info "Обновление установленных пакетов..."
apt upgrade -y 2>&1 | tee -a "$LOG_FILE"

# =============================================================================
# РАЗДЕЛ 2: УСТАНОВКА ПАКЕТОВ
# =============================================================================
log_step "Раздел 2: Установка необходимых пакетов"

PACKAGES=(
    unattended-upgrades    # Автоматические обновления безопасности
    apt-listchanges        # Уведомления об изменениях в пакетах
    sudo                   # Права суперпользователя
    ufw                    # Фаервол
    curl                   # Загрузка файлов
    git                    # Система контроля версий
    mc                     # Midnight Commander (файловый менеджер)
    fail2ban               # Защита от брутфорса
    htop                   # Мониторинг процессов
    nload                  # Мониторинг трафика
    net-tools              # Сетевые утилиты (ifconfig, netstat)
)

log_info "Установка пакетов: ${PACKAGES[*]}"
apt install -y "${PACKAGES[@]}" 2>&1 | tee -a "$LOG_FILE"

log_success "Все пакеты установлены"

# =============================================================================
# РАЗДЕЛ 3: НАСТРОЙКА AUTOMATIC UPDATES
# =============================================================================
log_step "Раздел 3: Настройка автоматических обновлений"

log_info "Настройка unattended-upgrades..."
dpkg-reconfigure --priority=low unattended-upgrades 2>&1 | tee -a "$LOG_FILE"

# Включение и запуск
systemctl enable unattended-upgrades
systemctl start unattended-upgrades

sleep 2

if systemctl is-active --quiet unattended-upgrades; then
    log_success "unattended-upgrades активен"
else
    log_error "unattended-upgrades не запустился"
    systemctl status unattended-upgrades --no-pager
fi

# =============================================================================
# РАЗДЕЛ 4: НАСТРОЙКА REPOSITORIES
# =============================================================================
log_step "Раздел 4: Настройка репозиториев"

if [ -f /etc/apt/sources.list ]; then
    cp -v /etc/apt/sources.list "$BACKUP_DIR/sources.list.backup" 2>/dev/null || true
fi

# Проверка наличия нужных репозиториев
if ! grep -q "contrib" /etc/apt/sources.list; then
    log_info "Добавление репозиториев contrib, non-free, non-free-firmware..."
    cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
    apt update 2>&1 | tee -a "$LOG_FILE"
    log_success "Репозитории обновлены"
else
    log_info "Репозитории уже настроены"
fi

# =============================================================================
# РАЗДЕЛ 5: НАСТРОЙКА HOSTNAME
# =============================================================================
log_step "Раздел 5: Настройка hostname"

read -p "Введите имя хоста (например, vps-01): " NEW_HOSTNAME

if [ ! -z "$NEW_HOSTNAME" ]; then
    # Бэкап /etc/hosts
    if [ -f /etc/hosts ]; then
        cp -v /etc/hosts "$BACKUP_DIR/hosts.backup" 2>/dev/null || true
    fi
    
    hostnamectl set-hostname "$NEW_HOSTNAME"
    
    # Обновление /etc/hosts
    if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
        echo "127.0.0.1       $NEW_HOSTNAME" >> /etc/hosts
        echo "127.0.0.1       $NEW_HOSTNAME.localdomain $NEW_HOSTNAME" >> /etc/hosts
    fi
    
    log_success "Hostname установлен: $NEW_HOSTNAME"
else
    log_warn "Hostname не изменен"
fi

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Базовая настройка завершена"

echo -e "${GREEN}✅${NC} Базовая настройка завершена!"
echo ""
echo -e "${YELLOW}📋 Выполнено:${NC}"
echo "  ✓ Обновлены пакеты"
echo "  ✓ Установлены: unattended-upgrades, apt-listchanges, sudo, ufw, curl, git, mc, fail2ban, htop, nload, net-tools"
echo "  ✓ Настроены автоматические обновления"
echo "  ✓ Настроены репозитории (contrib, non-free, non-free-firmware)"
echo "  ✓ Установлен hostname: ${NEW_HOSTNAME:-не изменен}"
echo ""
echo -e "${CYAN}📁 Бэкапы:${NC} $BACKUP_DIR"
echo ""
read -p "Нажмите Enter для продолжения..."
