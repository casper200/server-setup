#!/bin/bash
# =============================================================================
# Debian 13 Server - Диагностика системы
# =============================================================================
# Описание: Полная диагностика работы системы и установленных служб
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
    log_error "Запустите с правами root: sudo ./07-system-diagnostic.sh"
    exit 1
fi

# =============================================================================
# ЗАГРУЗКА КОНФИГУРАЦИИ
# =============================================================================
BACKUP_DIR=$(ls -td /root/backup_* 2>/dev/null | head -1)
DIAGNOSTIC_DIR="/root/diagnostic_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DIAGNOSTIC_DIR"
REPORT_FILE="$DIAGNOSTIC_DIR/diagnostic_report.txt"

log_info "Диагностика сохраняется в: $DIAGNOSTIC_DIR"

# =============================================================================
# ФУНКЦИЯ ЗАПИСИ В ОТЧЕТ
# =============================================================================
write_report() {
    echo "$1" >> "$REPORT_FILE"
}

# =============================================================================
# РАЗДЕЛ 1: СИСТЕМНАЯ ИНФОРМАЦИЯ
# =============================================================================
log_step "Раздел 1: Системная информация"

write_report "=========================================="
write_report "ДИАГНОСТИЧЕСКИЙ ОТЧЕТ СЕРВЕРА"
write_report "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
write_report "=========================================="
write_report ""

# Информация о системе
write_report "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ==="
write_report "Hostname: $(hostname)"
write_report "Версия Debian: $(lsb_release -d | cut -f2)"
write_report "Ядро: $(uname -r)"
write_report "Архитектура: $(uname -m)"
write_report "Время работы: $(uptime -p)"
write_report "Текущая нагрузка: $(uptime | awk -F'load average:' '{print $2}')"
write_report ""

echo -e "${YELLOW}Системная информация:${NC}"
echo "  Hostname: $(hostname)"
echo "  Версия: $(lsb_release -d | cut -f2)"
echo "  Ядро: $(uname -r)"
echo "  Время работы: $(uptime -p)"

# =============================================================================
# РАЗДЕЛ 2: РЕСУРСЫ
# =============================================================================
log_step "Раздел 2: Ресурсы системы"

write_report "=== РЕСУРСЫ СИСТЕМЫ ==="

# Память
write_report "--- ПАМЯТЬ ---"
free -h >> "$REPORT_FILE"
write_report ""

# Диски
write_report "--- ДИСКИ ---"
df -h >> "$REPORT_FILE"
write_report ""

# CPU
write_report "--- ПРОЦЕССОР ---"
lscpu | grep -E "Model name|CPU\(s\)|Thread|Core|Socket" >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}Память:${NC}"
free -h
echo -e "\n${YELLOW}Диски:${NC}"
df -h

# =============================================================================
# РАЗДЕЛ 3: СЕТЕВЫЕ НАСТРОЙКИ
# =============================================================================
log_step "Раздел 3: Сетевые настройки"

write_report "=== СЕТЕВЫЕ НАСТРОЙКИ ==="

# Интерфейсы
write_report "--- СЕТЕВЫЕ ИНТЕРФЕЙСЫ ---"
ip addr show >> "$REPORT_FILE"
write_report ""

# Маршруты
write_report "--- МАРШРУТЫ ---"
ip route show >> "$REPORT_FILE"
write_report ""

# DNS
write_report "--- DNS ---"
resolvectl status >> "$REPORT_FILE" 2>/dev/null || echo "systemd-resolved не активен" >> "$REPORT_FILE"
write_report ""

write_report "--- РАЗРЕШЕНИЕ ИМЕН ---"
nslookup google.com >> "$REPORT_FILE" 2>/dev/null || echo "DNS не работает" >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}Сетевые интерфейсы:${NC}"
ip addr show | grep -E "^[0-9]+:|inet |inet6 "
echo -e "\n${YELLOW}DNS:${NC}"
resolvectl status | head -10 2>/dev/null || echo "systemd-resolved не активен"

# =============================================================================
# РАЗДЕЛ 4: СЛУЖБЫ
# =============================================================================
log_step "Раздел 4: Проверка служб"

write_report "=== СЛУЖБЫ ==="

SERVICES=(
    "ssh"
    "ufw"
    "fail2ban"
    "systemd-resolved"
    "systemd-timesyncd"
    "systemd-networkd"
    "docker"
    "netbird"
)

write_report "--- СТАТУС СЛУЖБ ---"
for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        status="✅ АКТИВЕН"
        echo -e "${GREEN}✓${NC} $service: активен"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        status="⚠️  ВКЛЮЧЕН (не активен)"
        echo -e "${YELLOW}⚠️${NC} $service: включен, но не активен"
    else
        status="❌ НЕ УСТАНОВЛЕН"
        echo -e "${RED}✗${NC} $service: не установлен"
    fi
    write_report "$service: $status"
done
write_report ""

# =============================================================================
# РАЗДЕЛ 5: ОТКРЫТЫЕ ПОРТЫ
# =============================================================================
log_step "Раздел 5: Открытые порты"

write_report "=== ОТКРЫТЫЕ ПОРТЫ ==="
ss -tulpn >> "$REPORT_FILE" 2>/dev/null
write_report ""

echo -e "${YELLOW}Открытые порты:${NC}"
ss -tulpn | grep LISTEN

# =============================================================================
# РАЗДЕЛ 6: UFW
# =============================================================================
log_step "Раздел 6: Проверка UFW"

write_report "=== UFW ==="
ufw status verbose >> "$REPORT_FILE" 2>/dev/null || echo "UFW не установлен" >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}UFW статус:${NC}"
ufw status verbose 2>/dev/null || echo "UFW не установлен"

# =============================================================================
# РАЗДЕЛ 7: FAIL2BAN
# =============================================================================
log_step "Раздел 7: Проверка fail2ban"

write_report "=== FAIL2BAN ==="
if command -v fail2ban-client &>/dev/null; then
    fail2ban-client status >> "$REPORT_FILE" 2>/dev/null
    write_report ""
    fail2ban-client status sshd >> "$REPORT_FILE" 2>/dev/null || echo "sshd jail не настроен" >> "$REPORT_FILE"
else
    write_report "fail2ban не установлен"
fi
write_report ""

echo -e "${YELLOW}fail2ban статус:${NC}"
if command -v fail2ban-client &>/dev/null; then
    fail2ban-client status
    echo ""
    fail2ban-client status sshd 2>/dev/null || echo "sshd jail не настроен"
else
    echo "fail2ban не установлен"
fi

# =============================================================================
# РАЗДЕЛ 8: NTP
# =============================================================================
log_step "Раздел 8: Проверка NTP"

write_report "=== NTP ==="
timedatectl status >> "$REPORT_FILE" 2>/dev/null
write_report ""
timedatectl timesync-status >> "$REPORT_FILE" 2>/dev/null || echo "NTP не настроен" >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}NTP статус:${NC}"
timedatectl status | grep -E "Time zone|System clock|NTP"
timedatectl timesync-status 2>/dev/null || echo "NTP не настроен"

# =============================================================================
# РАЗДЕЛ 9: DOCKER
# =============================================================================
log_step "Раздел 9: Проверка Docker"

write_report "=== DOCKER ==="
if command -v docker &>/dev/null; then
    docker --version >> "$REPORT_FILE"
    docker info >> "$REPORT_FILE" 2>/dev/null
    write_report ""
    docker ps -a >> "$REPORT_FILE" 2>/dev/null
    write_report ""
    
    echo -e "${YELLOW}Docker:${NC}"
    docker --version
    docker ps -a | head -10
else
    write_report "Docker не установлен"
    echo "Docker не установлен"
fi

# =============================================================================
# РАЗДЕЛ 10: NETBIRD
# =============================================================================
log_step "Раздел 10: Проверка NetBird"

write_report "=== NETBIRD ==="
if command -v netbird &>/dev/null; then
    netbird status >> "$REPORT_FILE" 2>/dev/null || echo "NetBird не настроен" >> "$REPORT_FILE"
    write_report ""
    ip -br link show wt0 >> "$REPORT_FILE" 2>/dev/null || echo "Интерфейс wt0 не найден" >> "$REPORT_FILE"
    
    echo -e "${YELLOW}NetBird:${NC}"
    netbird status 2>/dev/null || echo "NetBird не настроен"
else
    write_report "NetBird не установлен"
    echo "NetBird не установлен"
fi

# =============================================================================
# РАЗДЕЛ 11: ЛОГИ
# =============================================================================
log_step "Раздел 11: Проверка логов"

write_report "=== ПОСЛЕДНИЕ ОШИБКИ В ЛОГАХ ==="
journalctl -p 3 --since "1 hour ago" --no-pager | tail -20 >> "$REPORT_FILE" 2>/dev/null
write_report ""

echo -e "${YELLOW}Последние ошибки в логах (за 1 час):${NC}"
journalctl -p 3 --since "1 hour ago" --no-pager | tail -10 || echo "Ошибок нет"

# =============================================================================
# РАЗДЕЛ 12: ПОЛЬЗОВАТЕЛИ
# =============================================================================
log_step "Раздел 12: Пользователи"

write_report "=== ПОЛЬЗОВАТЕЛИ ==="
write_report "Пользователи с sudo правами:"
getent group sudo | cut -d: -f4 >> "$REPORT_FILE" 2>/dev/null || echo "Группа sudo не найдена" >> "$REPORT_FILE"
write_report ""
write_report "Все пользователи:"
cut -d: -f1 /etc/passwd >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}Пользователи с sudo правами:${NC}"
getent group sudo | cut -d: -f4 2>/dev/null || echo "Группа sudo не найдена"

# =============================================================================
# РАЗДЕЛ 13: УСТАНОВКА NETDATA (МОНИТОРИНГ)
# =============================================================================
log_step "Раздел 13: Установка NetData (мониторинг)"

read -p "Установить NetData для мониторинга в реальном времени? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Установка NetData..."
    bash <(curl -Ss https://my-netdata.io/kickstart.sh) 2>&1 | tee -a "$REPORT_FILE"
    
    if systemctl is-active --quiet netdata; then
        log_success "NetData установлен и запущен"
        HOST_IP=$(ip addr show | grep -E "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
        echo -e "${CYAN}Доступ к NetData:${NC} http://${HOST_IP:-<IP_АДРЕС>}:19999"
    else
        log_error "NetData не запустился"
    fi
else
    log_info "Установка NetData пропущена"
fi

# =============================================================================
# РАЗДЕЛ 14: УСТАНОВКА NODE_EXPORTER (PROMETHEUS)
# =============================================================================
log_step "Раздел 14: Установка Node Exporter"

read -p "Установить Node Exporter для Prometheus? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Установка Node Exporter..."
    
    # Загрузка последней версии
    cd /tmp
    wget -q https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*.linux-amd64.tar.gz
    tar xvf node_exporter-*.linux-amd64.tar.gz 2>&1 | tee -a "$REPORT_FILE"
    mv node_exporter-*.linux-amd64/node_exporter /usr/local/bin/
    
    # Создание пользователя
    useradd -rs /bin/false node_exporter 2>/dev/null || true
    
    # Создание systemd сервиса
    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable --now node_exporter
    
    if systemctl is-active --quiet node_exporter; then
        log_success "Node Exporter установлен и запущен"
        HOST_IP=$(ip addr show | grep -E "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
        echo -e "${CYAN}Node Exporter доступен:${NC} http://${HOST_IP:-<IP_АДРЕС>}:9100/metrics"
    else
        log_error "Node Exporter не запустился"
    fi
else
    log_info "Установка Node Exporter пропущена"
fi

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Диагностика завершена"

echo -e "${GREEN}✅${NC} Диагностика завершена!"
echo ""
echo -e "${YELLOW}📋 Результаты:${NC}"
echo "  ✓ Собрана системная информация"
echo "  ✓ Проверены все службы"
echo "  ✓ Проверены сетевые настройки"
echo "  ✓ Проверены порты и UFW"
echo "  ✓ Проверен fail2ban"
echo "  ✓ Проверен NTP"
echo "  ✓ Проверен Docker (если установлен)"
echo "  ✓ Проверен NetBird (если установлен)"
echo "  ✓ Проверены логи"
echo "  ✓ Установлены инструменты мониторинга (опционально)"
echo ""
echo -e "${CYAN}📁 Директория диагностики:${NC} $DIAGNOSTIC_DIR"
echo -e "${CYAN}📄 Отчет:${NC} $REPORT_FILE"
echo ""
echo -e "${YELLOW}⚠️  Рекомендации:${NC}"
echo "  • Просмотрите отчет: cat $REPORT_FILE"
echo "  • Проверьте все службы на наличие ошибок"
echo "  • Убедитесь, что все порты открыты корректно"
echo ""

read -p "Нажмите Enter для продолжения..."
