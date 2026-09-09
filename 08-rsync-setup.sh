#!/bin/bash
# =============================================================================
# Debian 13 Server - Настройка rsync для бэкапов (ИСПРАВЛЕННАЯ)
# =============================================================================
# Описание: Настройка rsync, создание скриптов бэкапа, настройка cron
# Версия: 1.1
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
    log_error "Запустите с правами root: sudo ./08-rsync-setup.sh"
    exit 1
fi

# =============================================================================
# ЗАГРУЗКА КОНФИГУРАЦИИ
# =============================================================================
BACKUP_DIR=$(ls -td /root/backup_* 2>/dev/null | head -1)
source "$BACKUP_DIR/system_config.conf" 2>/dev/null || true
LOG_FILE="$BACKUP_DIR/rsync_setup.log"

# =============================================================================
# РАЗДЕЛ 1: УСТАНОВКА RSYNC
# =============================================================================
log_step "Раздел 1: Установка rsync"

apt install -y rsync 2>&1 | tee -a "$LOG_FILE"
log_success "rsync установлен"

# =============================================================================
# РАЗДЕЛ 2: СОЗДАНИЕ ДИРЕКТОРИЙ ДЛЯ БЭКАПОВ
# =============================================================================
log_step "Раздел 2: Создание директорий для бэкапов"

BACKUP_ROOT="/backup"
mkdir -p "$BACKUP_ROOT"
log_success "Директория создана: $BACKUP_ROOT"

mkdir -p "$BACKUP_ROOT"/{daily,weekly,monthly,logs}
log_success "Поддиректории созданы"

# =============================================================================
# РАЗДЕЛ 3: СОЗДАНИЕ СКРИПТА БЭКАПА (ИСПРАВЛЕННАЯ ВЕРСИЯ)
# =============================================================================
log_step "Раздел 3: Создание скрипта бэкапа"

cat > /usr/local/bin/backup.sh << 'EOF'
#!/bin/bash
# =============================================================================
# Debian 13 Server - Скрипт резервного копирования (rsync)
# =============================================================================
# Запуск: /usr/local/bin/backup.sh [daily|weekly|monthly]
# Cron: 0 2 * * * /usr/local/bin/backup.sh daily
#       0 3 * * 0 /usr/local/bin/backup.sh weekly
#       0 4 1 * * /usr/local/bin/backup.sh monthly
# =============================================================================

set -e

# =============================================================================
# КОНФИГУРАЦИЯ
# =============================================================================
BACKUP_ROOT="/backup"
BACKUP_TYPE="${1:-daily}"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$BACKUP_TYPE/$BACKUP_DATE"
LOG_FILE="$BACKUP_ROOT/logs/backup_${BACKUP_TYPE}_$(date +%Y%m%d).log"

# Цветной вывод
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() { log "${GREEN}[✓]${NC} $1"; }
log_warn() { log "${YELLOW}[!]${NC} $1"; }
log_error() { log "${RED}[✗]${NC} $1"; }

# =============================================================================
# ОПРЕДЕЛЕНИЕ КАТАЛОГОВ ДЛЯ БЭКАПА
# =============================================================================
BACKUP_DIRS=(
    "/etc"
    "/home"
    "/root/.ssh"
    "/usr/local/bin"
    "/opt"
)

ADDITIONAL_DIRS=(
    "/var/www"
    "/var/lib/docker"
    "/var/lib/mysql"
    "/var/lib/postgresql"
    "/srv"
    "/var/spool/cron"
)

# =============================================================================
# ФУНКЦИЯ БЭКАПА (С ПРОДОЛЖЕНИЕМ ПРИ ОШИБКЕ)
# =============================================================================
backup_dirs() {
    local source="$1"
    local target="$2"
    
    if [ -d "$source" ] && [ ! -L "$source" ]; then
        log_info "Бэкап: $source"
        if rsync -avz --delete --ignore-errors --exclude="*.pid" --exclude="*.sock" --exclude="tmp/*" --exclude="cache/*" "$source/" "$target/" 2>&1 | tee -a "$LOG_FILE"; then
            return 0
        else
            log_warn "rsync завершился с ошибкой для $source, но продолжаем..."
            return 1
        fi
    else
        log_warn "Пропуск: $source (не существует или является ссылкой)"
        return 1
    fi
}

# =============================================================================
# ОСНОВНАЯ ЛОГИКА
# =============================================================================
log "=========================================="
log "НАЧАЛО БЭКАПА: $BACKUP_TYPE"
log "=========================================="

mkdir -p "$BACKUP_DIR"
log_info "Директория бэкапа: $BACKUP_DIR"

# Бэкап основных каталогов
for dir in "${BACKUP_DIRS[@]}"; do
    target_name=$(basename "$dir")
    target_name="${target_name//./_}"
    target_name="${target_name//\//_}"
    backup_dirs "$dir" "$BACKUP_DIR/$target_name" || true
done

# Бэкап дополнительных каталогов (только если существуют)
for dir in "${ADDITIONAL_DIRS[@]}"; do
    if [ -d "$dir" ] && [ ! -L "$dir" ]; then
        target_name=$(basename "$dir")
        target_name="${target_name//./_}"
        target_name="${target_name//\//_}"
        backup_dirs "$dir" "$BACKUP_DIR/$target_name" || true
    fi
done

# =============================================================================
# СОЗДАНИЕ АРХИВА
# =============================================================================
log "--- Создание архива ---"

cd "$BACKUP_ROOT/$BACKUP_TYPE"

if tar -czf "${BACKUP_DATE}.tar.gz" "$BACKUP_DATE" 2>&1 | tee -a "$LOG_FILE"; then
    log_info "Архив создан: ${BACKUP_DATE}.tar.gz"
    rm -rf "$BACKUP_DIR"
    log_info "Временная папка удалена"
else
    log_error "ОШИБКА: архив не создан!"
    exit 1
fi

# =============================================================================
# УДАЛЕНИЕ СТАРЫХ БЭКАПОВ
# =============================================================================
log "--- Удаление старых бэкапов ---"

case "$BACKUP_TYPE" in
    daily)
        find "$BACKUP_ROOT/daily" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
        log_info "Старые ежедневные бэкапы удалены"
        ;;
    weekly)
        find "$BACKUP_ROOT/weekly" -name "*.tar.gz" -mtime +28 -delete 2>/dev/null
        log_info "Старые еженедельные бэкапы удалены"
        ;;
    monthly)
        find "$BACKUP_ROOT/monthly" -name "*.tar.gz" -mtime +365 -delete 2>/dev/null
        log_info "Старые ежемесячные бэкапы удалены"
        ;;
esac

# =============================================================================
# ИТОГО
# =============================================================================
BACKUP_SIZE=$(du -sh "$BACKUP_ROOT" 2>/dev/null | awk '{print $1}')
log "=========================================="
log_info "БЭКАП ЗАВЕРШЕН УСПЕШНО!"
log "Тип: $BACKUP_TYPE"
log "Файл: $BACKUP_DATE.tar.gz"
log "Общий размер бэкапов: $BACKUP_SIZE"
log "=========================================="

echo ""
echo -e "${GREEN}✅${NC} Бэкап завершен!"
echo -e "  Тип: $BACKUP_TYPE"
echo -e "  Файл: $BACKUP_DATE.tar.gz"
echo -e "  Размер: $BACKUP_SIZE"
EOF

chmod +x /usr/local/bin/backup.sh
log_success "Скрипт бэкапа создан: /usr/local/bin/backup.sh"

# =============================================================================
# РАЗДЕЛ 4: СОЗДАНИЕ СКРИПТА ВОССТАНОВЛЕНИЯ
# =============================================================================
log_step "Раздел 4: Создание скрипта восстановления"

cat > /usr/local/bin/restore.sh << 'EOF'
#!/bin/bash
# =============================================================================
# Debian 13 Server - Скрипт восстановления из бэкапа
# =============================================================================
# Использование: /usr/local/bin/restore.sh <путь_к_архиву>
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }

if [ -z "$1" ]; then
    echo "Использование: $0 <путь_к_архиву.tar.gz>"
    echo "Пример: $0 /backup/daily/20260101_020000.tar.gz"
    exit 1
fi

ARCHIVE="$1"

if [ ! -f "$ARCHIVE" ]; then
    log_error "Архив не найден: $ARCHIVE"
    exit 1
fi

log_info "Восстановление из: $ARCHIVE"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

tar -xzf "$ARCHIVE"
BACKUP_DATE=$(basename "$ARCHIVE" .tar.gz)

log_info "Распаковка завершена"

# Восстановление каталогов
for dir in etc home var_www var_lib_docker opt root_.ssh usr_local_bin cron; do
    if [ -d "$BACKUP_DATE/$dir" ]; then
        target="/${dir//_//}"
        target="${target//root_ssh/root/.ssh}"
        target="${target//usr_local_bin/usr/local/bin}"
        target="${target//var_www/var/www}"
        target="${target//var_lib_docker/var/lib/docker}"
        
        log_info "Восстановление: $target"
        rsync -av "$BACKUP_DATE/$dir/" "$target/" 2>/dev/null || true
    fi
done

# Восстановление баз данных
if [ -d "$BACKUP_DATE/mysql" ] && [ -f "$BACKUP_DATE/mysql/all_databases.sql" ]; then
    log_info "Восстановление MySQL..."
    mysql < "$BACKUP_DATE/mysql/all_databases.sql" 2>/dev/null || log_warn "MySQL восстановление не выполнено"
fi

if [ -d "$BACKUP_DATE/postgresql" ] && [ -f "$BACKUP_DATE/postgresql/all_databases.sql" ]; then
    log_info "Восстановление PostgreSQL..."
    psql -f "$BACKUP_DATE/postgresql/all_databases.sql" 2>/dev/null || log_warn "PostgreSQL восстановление не выполнено"
fi

log_info "Восстановление завершено"
rm -rf "$TEMP_DIR"
EOF

chmod +x /usr/local/bin/restore.sh
log_success "Скрипт восстановления создан: /usr/local/bin/restore.sh"

# =============================================================================
# РАЗДЕЛ 5: НАСТРОЙКА CRON (ТОЛЬКО ЕЖЕМЕСЯЧНЫЙ ПО УМОЛЧАНИЮ)
# =============================================================================
log_step "Раздел 5: Настройка cron для бэкапа"

# Проверка, есть ли уже настройки
if ! grep -q "backup.sh" /etc/crontab 2>/dev/null; then
    cat >> /etc/crontab << 'EOF'
# Резервное копирование (ежемесячное)
# 0 2 * * * root /usr/local/bin/backup.sh daily
# 0 3 * * 0 root /usr/local/bin/backup.sh weekly
0 4 1 * * root /usr/local/bin/backup.sh monthly
EOF
    log_success "Cron настроен (ежемесячный бэкап)"
    log_info "  • Ежемесячно 1-го числа в 4:00"
else
    log_info "Cron уже настроен"
fi

# =============================================================================
# РАЗДЕЛ 6: ТЕСТОВЫЙ ЗАПУСК
# =============================================================================
log_step "Раздел 6: Тестовый запуск бэкапа"

log_info "Запуск тестового бэкапа..."
/usr/local/bin/backup.sh monthly 2>&1 | head -30

if [ -f "/backup/monthly/$(date +%Y%m%d)*.tar.gz" ] 2>/dev/null; then
    log_success "Тестовый бэкап создан"
    ls -lh /backup/monthly/*.tar.gz 2>/dev/null | tail -1
else
    log_warn "Тестовый бэкап не найден, проверьте логи"
fi

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Настройка rsync завершена"

echo -e "${GREEN}✅${NC} Rsync и бэкапы настроены!"
echo ""
echo -e "${YELLOW}📋 Информация:${NC}"
echo "  • rsync: $(rsync --version | head -1)"
echo "  • Директория бэкапов: /backup/"
echo "  • Скрипт бэкапа: /usr/local/bin/backup.sh"
echo "  • Скрипт восстановления: /usr/local/bin/restore.sh"
echo ""
echo -e "${CYAN}Команды:${NC}"
echo "  # Запуск бэкапа вручную"
echo "  /usr/local/bin/backup.sh daily"
echo "  /usr/local/bin/backup.sh weekly"
echo "  /usr/local/bin/backup.sh monthly"
echo ""
echo "  # Восстановление"
echo "  /usr/local/bin/restore.sh /backup/daily/20260101_020000.tar.gz"
echo ""
echo -e "${CYAN}Cron задачи (автоматический бэкап):${NC}"
grep "backup.sh" /etc/crontab 2>/dev/null || echo "  Не настроен"
echo ""
read -p "Нажмите Enter для продолжения..."
