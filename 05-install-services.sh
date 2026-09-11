#!/bin/bash
# =============================================================================
# Debian 13 Server - Установка Docker, NetBird, NPM и RClone
# =============================================================================
# Описание: Интерактивная установка дополнительных системных сервисов
# Версия: 1.2 (С поддержкой RClone)
# =============================================================================

set -e
set -u

# =============================================================================
# ЦВЕТНОЙ ВЫВОД И ЛОГИКА
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
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

# Логирование работы скрипта в глобальный каталог
mkdir -p /backup/logs
LOG_FILE="/backup/logs/services_install_$(date +%Y%m%d).log"
exec > >(tee -i "$LOG_FILE") 2>&1

# =============================================================================
# МЕНЮ ВЫБОРА
# =============================================================================
log_step "Выбор сервисов для установки"

echo -e "${YELLOW}Выберите сервисы для установки (можно выбрать всё или по отдельности):${NC}"
echo "1) Docker + Docker Compose"
echo "2) NetBird (VPN)"
echo "3) Nginx Proxy Manager (Требует Docker)"
echo "4) RClone (Окружение для бэкапов в облако)"
echo "5) УСТАНОВИТЬ ВСЕ СЕРВИСЫ КАСКАДОМ"
echo "6) Выйти"
echo ""
read -p "Ваш выбор (1-6): " CHOICE

INSTALL_DOCKER=false
INSTALL_NETBIRD=false
INSTALL_NPM=false
INSTALL_RCLONE=false

case "$CHOICE" in
    1) INSTALL_DOCKER=true ;;
    2) INSTALL_NETBIRD=true ;;
    3) INSTALL_NPM=true ;;
    4) INSTALL_RCLONE=true ;;
    5) INSTALL_DOCKER=true; INSTALL_NETBIRD=true; INSTALL_NPM=true; INSTALL_RCLONE=true ;;
    6) exit 0 ;;
    *) log_error "Неверный выбор"; exit 1 ;;
esac

# =============================================================================
# 1. УСТАНОВКА DOCKER
# =============================================================================
if [ "$INSTALL_DOCKER" = true ]; then
    log_step "Установка Docker и Docker Compose"

    log_info "Очистка возможных старых конфликтующих пакетов..."
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    log_info "Обновление зависимостей..."
    apt update && apt install -y curl apt-transport-https ca-certificates gnupg lsb-release

    log_info "Запуск официального инсталлятора Docker..."
    curl -fsSL https://docker.com -o get-docker.sh
    sh get-docker.sh
    rm -f get-docker.sh

    # Интерактивное добавление пользователя в группу
    echo ""
    read -p "Введите имя вашего обычного пользователя (например, vasa) для работы с Docker без sudo: " DOCKER_USER
    if [ ! -z "$DOCKER_USER" ] && id "$DOCKER_USER" &>/dev/null; then
        usermod -aG docker "$DOCKER_USER"
        log_success "Пользователь $DOCKER_USER успешно добавлен в группу docker!"
    else
        log_warn "Пользователь не указан или не найден. Пропускаем."
    fi

    systemctl enable --now docker

    if systemctl is-active --quiet docker; then
        log_success "Docker успешно развернут и запущен: $(docker --version)"
    else
        log_error "Ошибка: Демон Docker не смог запуститься."
    fi
fi

# =============================================================================
# 2. УСТАНОВКА NETBIRD
# =============================================================================
if [ "$INSTALL_NETBIRD" = true ]; then
    log_step "Установка NetBird VPN"

    log_info "Импорт официальных ключей и репозитория NetBird..."
    mkdir -p /usr/share/keyrings
    curl -sSL https://netbird.io | gpg --dearmor --yes --output /usr/share/keyrings/netbird-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://netbird.io stable main' | tee /etc/apt/sources.list.d/netbird.list

    apt update && apt install -y netbird

    echo ""
    read -p "Если у вас есть готовый Setup Key от NetBird, введите его (или нажмите Enter для пропуска): " NETBIRD_KEY
    if [ ! -z "$NETBIRD_KEY" ]; then
        netbird up --setup-key "$NETBIRD_KEY"
        log_success "NetBird успешно подключен к сети!"
        netbird status
    else
        log_warn "Ключ не введен. Сервис установлен, но требует ручной авторизации через команду 'netbird up'"
    fi
fi

# =============================================================================
# 3. УСТАНОВКА NGINX PROXY MANAGER
# =============================================================================
if [ "$INSTALL_NPM" = true ]; then
    log_step "Установка Nginx Proxy Manager"

    if ! command -v docker &>/dev/null; then
        log_error "Критическая ошибка: Для работы NPM необходим Docker! Перезапустите скрипт и выберите пункт 1 или 5."
        exit 1
    fi

    log_info "Создание изолированной директории /opt/npm..."
    mkdir -p /opt/npm
    cd /opt/npm

    log_info "Генерация файла конфигурации docker-compose.yml..."
    cat > docker-compose.yml << 'EOF'
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

    log_info "Развертывание контейнера через Docker Compose..."
    docker compose up -d
    sleep 4

    if docker ps | grep -q "nginx-proxy-manager"; then
        log_success "Nginx Proxy Manager успешно запущен!"
        
        # Автоматическое определение текущего IP сервера для удобства вывода
        HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "<IP_АДРЕС>")
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "Панель управления доступна по адресу: ${GREEN}http://${HOST_IP}:81${NC}"
        echo -e "Данные для первого входа по умолчанию:"
        echo -e "  • Email:    ${WHITE}admin@example.com${NC}"
        echo -e "  • Password: ${WHITE}changeme${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    else
        log_error "Контейнер NPM не смог запуститься. Проверьте порты 80/443/81"
        docker compose logs --tail=20
    fi
fi

# =============================================================================
# 4. УСТАНОВКА RCLONE
# =============================================================================
if [ "$INSTALL_RCLONE" = true ]; then
    log_step "Установка утилиты работы с облаками RClone"

    apt install -y unzip
    if ! command -v rclone &>/dev/null; then
        log_info "Загрузка официального бинарного инсталлятора RClone..."
        curl https://rclone.org | bash
    else
        log_info "RClone уже присутствует в операционной системе."
    fi
    
    log_success "RClone готов к работе: $(rclone --version | head -1)"
    echo -e "\n${YELLOW}Следующий шаг для бэкапов:${NC}"
    echo -e "После завершения этого скрипта выполните команду: ${CYAN}rclone config${NC} для привязки вашего облака."
fi

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Установка выбранных сервисов завершена"

echo -e "${GREEN}✅ Процесс развертывания завершен успешно!${NC}"
echo -e "Полный лог установки сохранен в: ${WHITE}$LOG_FILE${NC}"
echo ""
echo -e "${YELLOW}📋 Статус компонентов на сервере:${NC}"
echo -e "  • Docker:            $(docker --version 2>/dev/null || echo -e '${RED}не установлен${NC}')"
echo -e "  • NetBird VPN:       $(command -v netbird &>/dev/null && echo -e '${GREEN}установлен${NC}' || echo -e '${RED}не установлен${NC}')"
echo -e "  • Nginx Proxy:       $(docker ps | grep -q "nginx-proxy-manager" && echo -e '${GREEN}активен на порту 81${NC}' || echo -e '${RED}не запущен / не установлен${NC}')"
echo -e "  • RClone Cloud:      $(command -v rclone &>/dev/null && echo -e '${GREEN}установлен${NC}' || echo -e '${RED}не установлен${NC}')"
echo ""
