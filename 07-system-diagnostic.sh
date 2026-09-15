#!/bin/bash
# =============================================================================
# Debian 13 Server - Диагностика системы
# =============================================================================
# Описание: Полная диагностика работы системы и установленных служб
# Версия: 1.1 (Добавлен RClone, таймауты, защита от зависаний)
# =============================================================================

# set -e НЕ используем — диагностика не должна падать на любой ошибке
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

log_info()    { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}\n${BLUE}►${NC} ${WHITE}$1${NC}\n${CYAN}═══════════════════════════════════════════════════${NC}\n"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }

# =============================================================================
# ПРОВЕРКА ROOT
# =============================================================================
if [[ $EUID -ne 0 ]]; then
    log_error "Запустите с правами root: sudo ./07-system-diagnostic.sh"
    exit 1
fi

# =============================================================================
# ДИРЕКТОРИЯ ДИАГНОСТИКИ
# =============================================================================
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

write_report "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ==="
write_report "Hostname: $(hostname)"
write_report "Версия Debian: $(lsb_release -d 2>/dev/null | cut -f2)"
write_report "Ядро: $(uname -r)"
write_report "Архитектура: $(uname -m)"
write_report "Время работы: $(uptime -p)"
write_report "Текущая нагрузка: $(uptime | awk -F'load average:' '{print $2}')"
write_report ""

echo -e "${YELLOW}Системная информация:${NC}"
echo "  Hostname: $(hostname)"
echo "  Версия: $(lsb_release -d 2>/dev/null | cut -f2)"
echo "  Ядро: $(uname -r)"
echo "  Время работы: $(uptime -p)"

# =============================================================================
# РАЗДЕЛ 2: РЕСУРСЫ
# =============================================================================
log_step "Раздел 2: Ресурсы системы"

write_report "=== РЕСУРСЫ СИСТЕМЫ ==="

write_report "--- ПАМЯТЬ ---"
free -h >> "$REPORT_FILE" 2>/dev/null
write_report ""

write_report "--- ДИСКИ ---"
df -h >> "$REPORT_FILE" 2>/dev/null
write_report ""

write_report "--- ПРОЦЕССОР ---"
lscpu 2>/dev/null | grep -E "Model name|CPU\(s\)|Thread|Core|Socket" >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}Память:${NC}"
free -h 2>/dev/null
echo -e "\n${YELLOW}Диски:${NC}"
df -h 2>/dev/null

# =============================================================================
# РАЗДЕЛ 3: СЕТЕВЫЕ НАСТРОЙКИ
# =============================================================================
log_step "Раздел 3: Сетевые настройки"

write_report "=== СЕТЕВЫЕ НАСТРОЙКИ ==="

write_report "--- СЕТЕВЫЕ ИНТЕРФЕЙСЫ ---"
ip addr show >> "$REPORT_FILE" 2>/dev/null
write_report ""

write_report "--- МАРШРУТЫ ---"
ip route show >> "$REPORT_FILE" 2>/dev/null
write_report ""

write_report "--- DNS ---"
resolvectl status >> "$REPORT_FILE" 2>/dev/null || echo "systemd-resolved не активен" >> "$REPORT_FILE"
write_report ""

write_report "--- РАЗРЕШЕНИЕ ИМЕН ---"
timeout 5 nslookup google.com >> "$REPORT_FILE" 2>/dev/null || echo "DNS не работает или таймаут" >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}Сетевые интерфейсы:${NC}"
ip addr show 2>/dev/null | grep -E "^[0-9]+:|inet |inet6 "
echo -e "\n${YELLOW}DNS:${NC}"
resolvectl status 2>/dev/null | head -10 || echo "systemd-resolved не активен"

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
        status="АКТИВЕН"
        echo -e "${GREEN}✓${NC} $service: активен"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        status="ВКЛЮЧЕН (не активен)"
        echo -e "${YELLOW}⚠${NC}  $service: включен, но не активен"
    else
        status="НЕ УСТАНОВЛЕН"
        echo -e "${RED}✗${NC} $service: не установлен"
    fi
    write_report "$service: $status"
done
write_report ""

# =============================================================================
# РАЗДЕЛ 4.5: ПРОВЕРКА RCLONE
# =============================================================================
log_step "Раздел 4.5: Проверка RClone"

write_report "=== RCLONE ==="
if command -v rclone &>/dev/null; then
    RCLONE_VERSION=$(rclone --version 2>/dev/null | head -1)
    write_report "Версия: $RCLONE_VERSION"
    write_report ""

    echo -e "${GREEN}✓${NC} RClone: $RCLONE_VERSION"

    RCLONE_REMOTES=$(rclone listremotes 2>/dev/null)
    if [ -n "$RCLONE_REMOTES" ]; then
        write_report "--- НАСТРОЕННЫЕ ОБЛАКА ---"
        echo "$RCLONE_REMOTES" >> "$REPORT_FILE"
        write_report ""

        echo -e "${YELLOW}Настроенные облака:${NC}"
        echo "$RCLONE_REMOTES" | while read -r remote; do
            [ -n "$remote" ] && echo -e "  ${GREEN}✓${NC} $remote"
        done

        write_report "--- ПРОВЕРКА ДОСТУПНОСТИ (таймаут 10с) ---"
        echo -e "${YELLOW}Проверка доступности:${NC}"
        echo "$RCLONE_REMOTES" | while read -r remote; do
            remote_name="${remote%:}"
            [ -z "$remote_name" ] && continue
            if timeout 10 rclone lsd "$remote" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $remote_name — доступен"
                write_report "$remote_name: доступен"
            else
                echo -e "  ${RED}✗${NC} $remote_name — НЕ доступен"
                write_report "$remote_name: НЕ доступен"
            fi
        done
    else
        write_report "Настроенных облаков нет (rclone config)"
        echo -e "${YELLOW}⚠${NC}  Настроенных облаков нет — выполните 'rclone config'"
    fi
else
    write_report "RClone не установлен"
    echo -e "${RED}✗${NC} RClone: не установлен"
fi
write_report ""

# =============================================================================
# РАЗДЕЛ 5: ОТКРЫТЫЕ ПОРТЫ
# =============================================================================
log_step "Раздел 5: Открытые порты"

write_report "=== ОТКРЫТЫЕ ПОРТЫ ==="
ss -tulpn >> "$REPORT_FILE" 2>/dev/null
write_report ""

echo -e "${YELLOW}Открытые порты:${NC}"
ss -tulpn 2>/dev/null | grep LISTEN

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
    fail2ban-client status 2>/dev/null || echo "fail2ban не отвечает"
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
timedatectl status 2>/dev/null | grep -E "Time zone|System clock|NTP"
timedatectl timesync-status 2>/dev/null || echo "NTP не настроен"

# =============================================================================
# РАЗДЕЛ 9: DOCKER
# =============================================================================
log_step "Раздел 9: Проверка Docker"

write_report "=== DOCKER ==="
if command -v docker &>/dev/null; then
    docker --version >> "$REPORT_FILE" 2>/dev/null
    docker info >> "$REPORT_FILE" 2>/dev/null
    write_report ""
    docker ps -a >> "$REPORT_FILE" 2>/dev/null
    write_report ""

    echo -e "${YELLOW}Docker:${NC}"
    docker --version 2>/dev/null
    docker ps -a 2>/dev/null | head -10
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
    timeout 5 netbird status >> "$REPORT_FILE" 2>/dev/null || echo "NetBird не отвечает" >> "$REPORT_FILE"
    write_report ""
    ip -br link show wt0 >> "$REPORT_FILE" 2>/dev/null || echo "Интерфейс wt0 не найден" >> "$REPORT_FILE"

    echo -e "${YELLOW}NetBird:${NC}"
    timeout 5 netbird status 2>/dev/null || echo "NetBird не отвечает или не настроен"
else
    write_report "NetBird не установлен"
    echo "NetBird не установлен"
fi

# =============================================================================
# РАЗДЕЛ 11: ЛОГИ
# =============================================================================
log_step "Раздел 11: Проверка логов"

write_report "=== ПОСЛЕДНИЕ ОШИБКИ В ЛОГАХ ==="
journalctl -p 3 --since "1 hour ago" --no-pager 2>/dev/null | tail -20 >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}Последние ошибки в логах (за 1 час):${NC}"
journalctl -p 3 --since "1 hour ago" --no-pager 2>/dev/null | tail -10 || echo "Ошибок нет"

# =============================================================================
# РАЗДЕЛ 12: ПОЛЬЗОВАТЕЛИ
# =============================================================================
log_step "Раздел 12: Пользователи"

write_report "=== ПОЛЬЗОВАТЕЛИ ==="
write_report "Пользователи с sudo правами:"
getent group sudo 2>/dev/null | cut -d: -f4 >> "$REPORT_FILE" || echo "Группа sudo не найдена" >> "$REPORT_FILE"
write_report ""
write_report "Все пользователи:"
cut -d: -f1 /etc/passwd 2>/dev/null >> "$REPORT_FILE"
write_report ""

echo -e "${YELLOW}Пользователи с sudo правами:${NC}"
getent group sudo 2>/dev/null | cut -d: -f4 || echo "Группа sudo не найдена"

# =============================================================================
# РАЗДЕЛ 13: УСТАНОВКА NETDATA (МОНИТОРИНГ)
# =============================================================================
log_step "Раздел 13: Установка NetData (мониторинг)"

read -p "Установить NetData для мониторинга в реальном времени? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Скачивание установщика NetData..."

    if timeout 20 curl -SsL https://my-netdata.io/kickstart.sh -o /tmp/netdata-kickstart.sh; then
        log_info "Установка NetData..."
        bash /tmp/netdata-kickstart.sh 2>&1 | tee -a "$REPORT_FILE" || log_warn "Установщик NetData завершился с ошибками"
        rm -f /tmp/netdata-kickstart.sh

        if systemctl is-active --quiet netdata 2>/dev/null; then
            log_success "NetData установлен и запущен"
            HOST_IP=$(ip addr show 2>/dev/null | grep -E "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
            echo -e "${CYAN}Доступ к NetData:${NC} http://${HOST_IP:-<IP_АДРЕС>}:19999"
        else
            log_error "NetData не запустился"
        fi
    else
        log_error "Не удалось скачать установщик NetData"
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

    cd /tmp

    if wget -q https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*.linux-amd64.tar.gz 2>/dev/null; then
        if tar xzf node_exporter-*.linux-amd64.tar.gz 2>&1 | tee -a "$REPORT_FILE"; then
            mv node_exporter-*.linux-amd64/node_exporter /usr/local/bin/ 2>/dev/null || true
            rm -rf node_exporter-*.linux-amd64.tar.gz node_exporter-*.linux-amd64

            useradd -rs /bin/false node_exporter 2>/dev/null || true

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

            systemctl daemon-reload 2>/dev/null
            systemctl enable --now node_exporter 2>/dev/null

            if systemctl is-active --quiet node_exporter 2>/dev/null; then
                log_success "Node Exporter установлен и запущен"
                HOST_IP=$(ip addr show 2>/dev/null | grep -E "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
                echo -e "${CYAN}Node Exporter доступен:${NC} http://${HOST_IP:-<IP_АДРЕС>}:9100/metrics"
            else
                log_error "Node Exporter не запустился"
            fi
        else
            log_error "Не удалось распаковать Node Exporter"
        fi
    else
        log_error "Не удалось скачать Node Exporter"
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
echo "  ✓ Проверен RClone (если установлен)"
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
