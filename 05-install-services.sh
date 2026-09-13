#!/bin/bash
# =============================================================================
# Debian 12/13 Server - Установка Docker, NetBird, NPM и RClone
# =============================================================================
# Описание: Установка отсутствующего ПО. Не падает при ошибках.
# Версия: 2.1 (Исправлены галочки в проверке)
# =============================================================================

# НЕ используем set -e — скрипт не должен падать при ошибках

# =============================================================================
# ЦВЕТНОЙ ВЫВОД
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}\n${BLUE}►${NC} ${WHITE}$1${NC}\n${CYAN}═══════════════════════════════════════════════════${NC}\n"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }

# =============================================================================
# ПРОВЕРКА ROOT
# =============================================================================
if [[ $EUID -ne 0 ]]; then
    log_error "Запустите с правами root: sudo $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"

# =============================================================================
# ЛОГИРОВАНИЕ
# =============================================================================
mkdir -p /backup/logs 2>/dev/null
LOG_FILE="/backup/logs/services_install_$(date +%Y%m%d).log"
log_to_file() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null; }

# =============================================================================
# СБОР ВЕРСИЙ УСТАНОВЛЕННОГО ПО
# =============================================================================
log_step "Проверка установленного ПО"

DOCKER_VER=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
NETBIRD_VER=$(netbird version 2>/dev/null | head -1)
RCLONE_VER=$(rclone --version 2>/dev/null | head -1 | awk '{print $2}')
NPM_RUNNING=$(docker ps --format '{{.Image}}' 2>/dev/null | grep -c "nginx-proxy-manager")

# Docker
if [ -n "$DOCKER_VER" ]; then
    echo -e "  ${GREEN}✓${NC} Docker:    $DOCKER_VER"
else
    echo -e "  ${RED}✗${NC} Docker:    не установлен"
fi

# NetBird
if [ -n "$NETBIRD_VER" ]; then
    echo -e "  ${GREEN}✓${NC} NetBird:   $NETBIRD_VER"
else
    echo -e "  ${RED}✗${NC} NetBird:   не установлен"
fi

# NPM
if [ "$NPM_RUNNING" -gt 0 ]; then
    NPM_ID=$(docker ps -q --filter "ancestor=jc21/nginx-proxy-manager" 2>/dev/null | head -1)
    NPM_VER=""
    [ -n "$NPM_ID" ] && NPM_VER=$(docker exec "$NPM_ID" cat package.json 2>/dev/null | grep -oP '"version":\s*"\K[^"]+' | head -1)
    echo -e "  ${GREEN}✓${NC} NPM:       ${NPM_VER:-запущен}"
else
    echo -e "  ${RED}✗${NC} NPM:       не установлен"
fi

# RClone
if [ -n "$RCLONE_VER" ]; then
    echo -e "  ${GREEN}✓${NC} RClone:    $RCLONE_VER"
else
    echo -e "  ${RED}✗${NC} RClone:    не установлен"
fi

log_to_file "Проверка: Docker=$DOCKER_VER NetBird=$NETBIRD_VER NPM=$NPM_RUNNING RClone=$RCLONE_VER"

# =============================================================================
# МЕНЮ
# =============================================================================
log_step "Выбор сервисов"

echo "  1) Docker + Docker Compose"
echo "  2) NetBird (VPN)"
echo "  3) Nginx Proxy Manager"
echo "  4) RClone"
echo "  5) Установить всё отсутствующее"
echo "  6) Выйти"
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
    5)
        [ -z "$DOCKER_VER" ]  && INSTALL_DOCKER=true
        [ -z "$NETBIRD_VER" ] && INSTALL_NETBIRD=true
        [ "$NPM_RUNNING" -eq 0 ] && INSTALL_NPM=true
        [ -z "$RCLONE_VER" ]  && INSTALL_RCLONE=true

        if [ "$INSTALL_DOCKER" = false ] && [ "$INSTALL_NETBIRD" = false ] && \
           [ "$INSTALL_NPM" = false ] && [ "$INSTALL_RCLONE" = false ]; then
            log_success "Все сервисы уже установлены!"
            exit 0
        fi
        ;;
    6) exit 0 ;;
    *) log_error "Неверный выбор. Выход."; exit 1 ;;
esac

# =============================================================================
# APT UPDATE
# =============================================================================
log_step "Обновление списка пакетов"
apt update 2>&1 | tail -3 || log_warn "apt update завершился с ошибкой"

# =============================================================================
# 1. DOCKER
# =============================================================================
if [ "$INSTALL_DOCKER" = true ]; then
    log_step "Установка Docker"

    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    apt install -y curl apt-transport-https ca-certificates gnupg lsb-release 2>/dev/null || true

    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null
    if [ -s /tmp/get-docker.sh ]; then
        sh /tmp/get-docker.sh 2>&1 | tail -5 || log_warn "Установщик Docker завершился с предупреждениями"
        rm -f /tmp/get-docker.sh
    else
        log_error "Не удалось скачать инсталлятор Docker"
    fi

    if [ "$REAL_USER" != "root" ] && id "$REAL_USER" &>/dev/null; then
        usermod -aG docker "$REAL_USER" 2>/dev/null || true
        log_warn "Пользователь $REAL_USER добавлен в группу docker"
        log_warn "Для применения прав выйдите из SSH и зайдите заново"
    fi

    systemctl enable --now docker 2>/dev/null || true

    if systemctl is-active --quiet docker; then
        log_success "Docker: $(docker --version)"
        log_to_file "Docker: $(docker --version)"
    else
        log_error "Docker не запустился. Проверьте: systemctl status docker"
    fi
else
    [ -n "$DOCKER_VER" ] && log_info "Docker: пропущено (уже установлен)"
fi

# =============================================================================
# 2. NETBIRD
# =============================================================================
if [ "$INSTALL_NETBIRD" = true ]; then
    log_step "Установка NetBird"

    # Проверяем, есть ли уже ключ и репозиторий
    if [ ! -f /usr/share/keyrings/netbird-archive-keyring.gpg ]; then
        log_info "Импорт GPG-ключа NetBird..."
        mkdir -p /usr/share/keyrings
        curl -sSL https://pkgs.netbird.io/debian/public.key \
            | gpg --dearmor --yes --output /usr/share/keyrings/netbird-archive-keyring.gpg 2>/dev/null || true
    else
        log_info "GPG-ключ NetBird уже установлен"
    fi

    if [ ! -f /etc/apt/sources.list.d/netbird.list ]; then
        log_info "Добавление репозитория NetBird..."
        echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' \
            | tee /etc/apt/sources.list.d/netbird.list >/dev/null 2>&1 || true
    else
        log_info "Репозиторий NetBird уже настроен"
    fi

    apt update 2>/dev/null
    apt install -y netbird 2>/dev/null || log_error "Не удалось установить NetBird"

    NB_VER=$(netbird version 2>/dev/null | head -1)
    if [ -n "$NB_VER" ]; then
        log_success "NetBird: $NB_VER"
    else
        log_error "NetBird не установлен"
    fi

    echo ""
    echo -e "${YELLOW}Способы подключения NetBird:${NC}"
    echo "  1) Setup Key"
    echo "  2) SSO (ссылка в браузере)"
    echo "  3) Пропустить"
    read -p "Ваш выбор (1-3): " NB_MODE

    case "$NB_MODE" in
        1)
            read -p "Setup Key: " NB_KEY
            if [ -n "$NB_KEY" ]; then
                netbird up --setup-key "$NB_KEY" 2>&1 | tail -3 || log_warn "Ключ не сработал — создайте новый Reusable ключ"
            else
                log_warn "Ключ не введён"
            fi
            ;;
        2)
            netbird up 2>&1 | head -10 || log_warn "SSO-вход не удался"
            ;;
        3)
            log_warn "Пропущено. Подключите позже: sudo netbird up"
            ;;
        *)
            log_warn "Неверный ввод. Пропущено."
            ;;
    esac

    netbird status 2>/dev/null | head -3 || true
    log_to_file "NetBird: установлен"
else
    [ -n "$NETBIRD_VER" ] && log_info "NetBird: пропущено (уже установлен)"
fi

# =============================================================================
# 3. NGINX PROXY MANAGER
# =============================================================================
if [ "$INSTALL_NPM" = true ]; then
    log_step "Установка Nginx Proxy Manager"

    if ! command -v docker &>/dev/null; then
        log_error "NPM требует Docker. Сначала установите Docker (пункт 1)."
    else
        mkdir -p /opt/npm
        cd /opt/npm

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

        docker compose up -d 2>&1 | tail -5 || log_error "Не удалось запустить NPM"
        sleep 5

        if docker ps --format '{{.Image}}' 2>/dev/null | grep -q "nginx-proxy-manager"; then
            log_success "NPM запущен"
            HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "<IP>")
            echo -e "\n  Панель: ${GREEN}http://${HOST_IP}:81${NC}"
            echo -e "  Логин:  admin@example.com"
            echo -e "  Пароль: changeme\n"
            log_to_file "NPM запущен на ${HOST_IP}:81"
        else
            log_error "NPM не запустился. Проверьте порты 80/443/81"
        fi
    fi
else
    [ "$NPM_RUNNING" -gt 0 ] && log_info "NPM: пропущено (уже запущен)"
fi

# =============================================================================
# 4. RCLONE
# =============================================================================
if [ "$INSTALL_RCLONE" = true ]; then
    log_step "Установка RClone"

    apt install -y unzip curl 2>/dev/null || true

    if ! command -v rclone &>/dev/null; then
        curl https://rclone.org/install.sh 2>/dev/null | bash 2>&1 | tail -3 || log_error "Не удалось установить RClone"
    fi

    if command -v rclone &>/dev/null; then
        log_success "RClone: $(rclone --version | head -1)"
        log_to_file "RClone: $(rclone --version | head -1)"
    else
        log_error "RClone не установлен"
    fi

    echo -e "\n  ${YELLOW}Настройте облако:${NC} rclone config\n"
else
    [ -n "$RCLONE_VER" ] && log_info "RClone: пропущено (уже установлен)"
fi

# =============================================================================
# ИТОГ
# =============================================================================
log_step "Готово"

echo -e "${YELLOW}📋 Финальный статус:${NC}"

# Docker
if docker --version &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Docker:    $(docker --version | awk '{print $3}' | tr -d ',')"
else
    echo -e "  ${RED}✗${NC} Docker:    не установлен"
fi

# NetBird
if netbird version &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} NetBird:   $(netbird version | head -1)"
else
    echo -e "  ${RED}✗${NC} NetBird:   не установлен"
fi

# NPM
if docker ps --format '{{.Image}}' 2>/dev/null | grep -q "nginx-proxy-manager"; then
    NPM_ID=$(docker ps -q --filter "ancestor=jc21/nginx-proxy-manager" 2>/dev/null | head -1)
    NPM_VER=""
    [ -n "$NPM_ID" ] && NPM_VER=$(docker exec "$NPM_ID" cat package.json 2>/dev/null | grep -oP '"version":\s*"\K[^"]+' | head -1)
    echo -e "  ${GREEN}✓${NC} NPM:       ${NPM_VER:-запущен}"
else
    echo -e "  ${RED}✗${NC} NPM:       не установлен"
fi

# RClone
if rclone --version &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} RClone:    $(rclone --version | head -1 | awk '{print $2}')"
else
    echo -e "  ${RED}✗${NC} RClone:    не установлен"
fi

echo ""
echo -e "Лог: ${WHITE}$LOG_FILE${NC}"
echo ""
read -p "Нажмите Enter для выхода..."
