#!/bin/bash
# =============================================================================
# Debian 13 Server - Установка Docker, NetBird, Nginx Proxy Manager
# =============================================================================
# Описание: Установка дополнительных сервисов
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
    log_error "Запустите с правами root: sudo ./05-install-services.sh"
    exit 1
fi

BACKUP_DIR=$(ls -td /root/backup_* 2>/dev/null | head -1)
LOG_FILE="$BACKUP_DIR/services_install.log"

# =============================================================================
# МЕНЮ ВЫБОРА
# =============================================================================
log_step "Выбор сервисов для установки"

echo -e "${YELLOW}Выберите сервисы для установки:${NC}"
echo "1) Docker + Docker Compose"
echo "2) NetBird (VPN)"
echo "3) Nginx Proxy Manager"
echo "4) Все сервисы"
echo "5) Выйти"
read -p "Ваш выбор (1-5): " CHOICE

case "$CHOICE" in
    1) INSTALL_DOCKER=true ;;
    2) INSTALL_NETBIRD=true ;;
    3) INSTALL_NPM=true ;;
    4) INSTALL_DOCKER=true; INSTALL_NETBIRD=true; INSTALL_NPM=true ;;
    5) exit 0 ;;
    *) log_error "Неверный выбор"; exit 1 ;;
esac

# =============================================================================
# УСТАНОВКА DOCKER
# =============================================================================
if [ "${INSTALL_DOCKER:-false}" = true ]; then
    log_step "Установка Docker"

    log_info "Удаление старых версий..."
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    log_info "Установка зависимостей..."
    apt update
    apt install -y curl apt-transport-https ca-certificates gnupg lsb-release

    log_info "Загрузка и установка Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh

    # Добавление пользователя в группу docker
    read -p "Введите имя пользователя для добавления в группу docker: " DOCKER_USER
    if [ ! -z "$DOCKER_USER" ] && id "$DOCKER_USER" &>/dev/null; then
        usermod -aG docker "$DOCKER_USER"
        log_success "Пользователь $DOCKER_USER добавлен в группу docker"
    fi

    systemctl enable --now docker

    if systemctl is-active --quiet docker; then
        log_success "Docker установлен и запущен"
        docker --version
    else
        log_error "Docker не запустился"
    fi
fi

# =============================================================================
# УСТАНОВКА NETBIRD
# =============================================================================
if [ "${INSTALL_NETBIRD:-false}" = true ]; then
    log_step "Установка NetBird"

    log_info "Добавление репозитория NetBird..."
    curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --output /usr/share/keyrings/netbird-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' | tee /etc/apt/sources.list.d/netbird.list

    apt update
    apt install -y netbird

    read -p "Введите Setup Key для NetBird: " NETBIRD_KEY
    if [ ! -z "$NETBIRD_KEY" ]; then
        netbird up --setup-key "$NETBIRD_KEY"

        if systemctl is-enabled --quiet netbird 2>/dev/null; then
            log_success "NetBird установлен и настроен"
            netbird status
            ip -br link show wt0
        else
            log_error "NetBird не настроен"
        fi
    else
        log_warn "Setup Key не введен, пропускаем настройку"
    fi
fi

# =============================================================================
# УСТАНОВКА NPM
# =============================================================================
if [ "${INSTALL_NPM:-false}" = true ]; then
    log_step "Установка Nginx Proxy Manager"

    if ! command -v docker &>/dev/null; then
        log_error "Docker не установлен! Сначала установите Docker"
        exit 1
    fi

    log_info "Создание директории для NPM..."
    mkdir -p /opt/npm
    cd /opt/npm

    log_info "Создание docker-compose.yml..."
    cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

    log_info "Запуск NPM..."
    docker compose up -d

    sleep 5

    if docker ps | grep -q "nginx-proxy-manager"; then
        log_success "Nginx Proxy Manager запущен"

        HOST_IP=$(ip addr show | grep -E "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
        echo ""
        echo -e "${CYAN}Доступ к панели управления:${NC}"
        echo -e "http://${HOST_IP:-<IP_АДРЕС>}:81"
        echo ""
        echo -e "${YELLOW}Логин по умолчанию:${NC}"
        echo "  Email: admin@example.com"
        echo "  Password: changeme"
    else
        log_error "NPM не запустился"
        docker compose logs
    fi
fi

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Установка сервисов завершена"

echo -e "${GREEN}✅${NC} Установка завершена!"
echo ""
echo -e "${YELLOW}📋 Установленные сервисы:${NC}"
[ "${INSTALL_DOCKER:-false}" = true ] && echo "  • Docker: $(docker --version 2>/dev/null || echo 'не установлен')"
[ "${INSTALL_NETBIRD:-false}" = true ] && echo "  • NetBird: установлен"
[ "${INSTALL_NPM:-false}" = true ] && echo "  • Nginx Proxy Manager: порт 81"
echo ""
echo -e "${CYAN}📁 Бэкапы:${NC} $BACKUP_DIR"
