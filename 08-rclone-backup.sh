#!/bin/bash
# =============================================================================
# Debian 13 Server - Бэкап ДАННЫХ + загрузка в облако через rclone
# =============================================================================
# Описание: Установка rclone, настройка облака rclon config (ручками) 
# см. readme.md, бэкап данных, cron
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
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}\n${BLUE}►${NC} ${WHITE}$1${NC}\n${CYAN}═══════════════════════════════════════════════════${NC}\n"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Запустите с правами root: sudo ./08-rclone-backup.sh"
    exit 1
fi

# =============================================================================
# РАЗДЕЛ 1: УСТАНОВКА RCLONE
# =============================================================================
log_step "Раздел 1: Установка rclone"

apt update
apt install -y curl unzip 2>&1

if ! command -v rclone &>/dev/null; then
    log_info "Установка rclone..."
    curl https://rclone.org/install.sh | bash 2>&1
fi

log_success "rclone: $(rclone --version | head -1)"


# =============================================================================
# РАЗДЕЛ 2: СОЗДАНИЕ ДИРЕКТОРИЙ
# =============================================================================
log_step "Раздел 3: Создание директорий"

mkdir -p /backup/data /backup/logs
log_success "Создано: /backup/data, /backup/logs"

# =============================================================================
# РАЗДЕЛ 4: СКРИПТ БЭКАПА ДАННЫХ
# =============================================================================
log_step "Раздел 4: Создание скрипта бэкапа данных"

cat > /usr/local/bin/backup-data.sh << 'EOF'
#!/bin/bash
# =============================================================================
# Debian 13 Server - Бэкап ТОЛЬКО ДАННЫХ
# =============================================================================

set -e

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/backup/data/data_${BACKUP_DATE}.tar.gz"
LOG_FILE="/backup/logs/backup_$(date +%Y%m%d).log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log_info() { log "${GREEN}[✓]${NC} $1"; }
log_warn() { log "${YELLOW}[!]${NC} $1"; }
log_error() { log "${RED}[✗]${NC} $1"; }

# Каталоги с ДАННЫМИ
DATA_DIRS=(
    "/opt/npm"
    "/var/lib/docker"
    "/var/lib/mysql"
    "/var/lib/postgresql"
    "/var/www"
    "/etc/netbird"
    "/home"
    "/root/.ssh"
    "/etc/crontab"
    "/var/spool/cron"
)

log "=========================================="
log "НАЧАЛО БЭКАПА ДАННЫХ"
log "=========================================="

EXISTING_DIRS=()
for dir in "${DATA_DIRS[@]}"; do
    if [ -e "$dir" ]; then
        EXISTING_DIRS+=("$dir")
        log_info "Найден: $dir"
    else
        log_warn "Пропуск: $dir"
    fi
done

if [ ${#EXISTING_DIRS[@]} -eq 0 ]; then
    log_error "Нет данных для бэкапа!"
    exit 1
fi

log "--- Создание архива ---"
if tar -czf "$BACKUP_FILE" "${EXISTING_DIRS[@]}" 2>/dev/null; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | awk '{print $1}')
    log_info "Архив создан: $BACKUP_FILE ($BACKUP_SIZE)"
else
    log_error "Ошибка создания архива!"
    exit 1
fi

# Удаление старых локальных бэкапов (7 дней)
find /backup/data -name "data_*.tar.gz" -mtime +7 -delete 2>/dev/null
log_info "Локальные бэкапы старше 7 дней удалены"

log "=========================================="
log_info "БЭКАП ЗАВЕРШЕН!"
log "Файл: $BACKUP_FILE"
log "Размер: $BACKUP_SIZE"
log "=========================================="

echo ""
echo -e "${GREEN}✅${NC} Бэкап данных завершен!"
echo -e "  Файл: $BACKUP_FILE"
echo -e "  Размер: $BACKUP_SIZE"
EOF

chmod +x /usr/local/bin/backup-data.sh
log_success "Создан: /usr/local/bin/backup-data.sh"

# =============================================================================
# РАЗДЕЛ 5: СКРИПТ ЗАГРУЗКИ В ОБЛАКО
# =============================================================================
log_step "Раздел 5: Создание скрипта загрузки в облако"

cat > /usr/local/bin/upload-backup.sh << EOF
#!/bin/bash
# =============================================================================
# Debian 13 Server - Загрузка бэкапа в облако ($RCLONE_REMOTE)
# =============================================================================

set -e

RCLONE_REMOTE="$RCLONE_REMOTE"
LOG_FILE="/backup/logs/upload_\$(date +%Y%m%d).log"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"; }

BACKUP_FILE=\$(ls -t /backup/data/data_*.tar.gz 2>/dev/null | head -1)

if [ -z "\$BACKUP_FILE" ]; then
    log "⚠️  Нет файлов для загрузки"
    exit 1
fi

BACKUP_NAME=\$(basename "\$BACKUP_FILE")
BACKUP_SIZE=\$(du -h "\$BACKUP_FILE" | awk '{print \$1}')

log "Загрузка: \$BACKUP_NAME (\$BACKUP_SIZE)"

rclone mkdir "\$RCLONE_REMOTE:backups" 2>/dev/null || true

if rclone copy "\$BACKUP_FILE" "\$RCLONE_REMOTE:backups/"; then
    log "✅ Загрузка завершена: \$BACKUP_NAME"
    rclone delete --min-age 30d "\$RCLONE_REMOTE:backups/" 2>/dev/null || true
    log "✅ Старые бэкапы в облаке удалены (30 дней)"
else
    log "❌ Ошибка загрузки!"
    exit 1
fi
EOF

chmod +x /usr/local/bin/upload-backup.sh
log_success "Создан: /usr/local/bin/upload-backup.sh"

# =============================================================================
# РАЗДЕЛ 6: СКРИПТ ВОССТАНОВЛЕНИЯ
# =============================================================================
log_step "Раздел 6: Создание скрипта восстановления"

cat > /usr/local/bin/restore-data.sh << 'EOF'
#!/bin/bash
# =============================================================================
# Debian 13 Server - Восстановление данных
# =============================================================================
# Использование: /usr/local/bin/restore-data.sh <архив.tar.gz>
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

if [ -z "$1" ]; then
    echo "Использование: $0 <архив.tar.gz>"
    exit 1
fi

ARCHIVE="$1"

if [ ! -f "$ARCHIVE" ]; then
    log_error "Архив не найден: $ARCHIVE"
    exit 1
fi

log_info "Восстановление из: $ARCHIVE"
log_warn "ВНИМАНИЕ! Данные будут перезаписаны!"
read -p "Продолжить? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Отменено"
    exit 1
fi

cd /
tar -xzf "$ARCHIVE" 2>/dev/null

log_success "Данные восстановлены!"
log_warn "Перезапустите службы: systemctl restart docker netbird"
EOF

chmod +x /usr/local/bin/restore-data.sh
log_success "Создан: /usr/local/bin/restore-data.sh"

# =============================================================================
# РАЗДЕЛ 7: CRON
# =============================================================================
log_step "Раздел 7: Настройка cron"

if ! grep -q "backup-data.sh" /etc/crontab 2>/dev/null; then
    cat >> /etc/crontab << 'EOF'

# Резервное копирование данных
0 2 * * * root /usr/local/bin/backup-data.sh
0 3 * * * root /usr/local/bin/upload-backup.sh
EOF
    log_success "Cron настроен: бэкап 2:00, загрузка 3:00"
fi

# =============================================================================
# РАЗДЕЛ 8: ТЕСТ
# =============================================================================
log_step "Раздел 8: Тестовый запуск"

/usr/local/bin/backup-data.sh
/usr/local/bin/upload-backup.sh

# =============================================================================
# ИТОГ
# =============================================================================
log_step "Готово"

echo -e "${GREEN}✅${NC} Бэкап данных настроен!"
echo ""
echo -e "${CYAN}Команды:${NC}"
echo "  Бэкап:        /usr/local/bin/backup-data.sh"
echo "  В облако:     /usr/local/bin/upload-backup.sh"
echo "  Восстановить: /usr/local/bin/restore-data.sh <архив>"
echo ""
echo -e "${CYAN}Облако:${NC} $RCLONE_REMOTE"
echo -e "${CYAN}Cron:${NC} 2:00 (бэкап), 3:00 (загрузка)"
echo ""
