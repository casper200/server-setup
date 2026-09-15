#!/bin/bash
# =============================================================================
# Шаг 8: Настройка локального бэкапа данных и выгрузки в облако RClone
# =============================================================================
# Описание: Создает локальный бэкап и интерактивно привязывает его к облаку.
#           Автоматически сортирует бэкапы в облаке по папкам с Hostname.
# Версия: 2.1 (С привязкой к Hostname сервера)
# =============================================================================

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[✗] Ошибка: Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

echo -e "${CYAN}=====================================================================${NC}"
echo -e "${CYAN}===         НАСТРОЙКА И АВТОМАТИЗАЦИЯ СИСТЕМЫ БЭКАПОВ             ===${NC}"
echo -e "${CYAN}=====================================================================${NC}"

# =============================================================================
# ЭТАП 1: НАСТРОЙКА ЛОКАЛЬНОГО БЭКАПА
# =============================================================================
echo -e "\n${BLUE}[1/2] Проверка локальной структуры папок...${NC}"

mkdir -p /backup/data /backup/logs
echo -e "${GREEN}[✓]${NC} Директории готовы: /backup/data, /backup/logs"

# Создаем скрипт локального архивирования
cat > /usr/local/bin/backup-data.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/backup/data/data_${BACKUP_DATE}.tar.gz"
LOG_FILE="/backup/logs/backup_$(date +%Y%m%d).log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local clean_msg
    clean_msg=$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${clean_msg}" >> "$LOG_FILE"
}
log_info() { echo -e "${GREEN}[✓]${NC} $1"; log "[✓] $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; log "[!] $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; log "[✗] $1"; }

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
log "НАЧАЛО ЛОКАЛЬНОГО БЭКАПА ДАННЫХ"
log "=========================================="

EXISTING_DIRS=()
for dir in "${DATA_DIRS[@]}"; do
    if [ -e "$dir" ]; then
        EXISTING_DIRS+=("$dir")
        log_info "Найден каталог: $dir"
    else
        log_warn "Пропущен (отсутствует): $dir"
    fi
done

if [ ${#EXISTING_DIRS[@]} -eq 0 ]; then
    log_error "Критическая ошибка: Нет доступных данных для архивации!"
    exit 1
fi

echo -e "${YELLOW}[...] Сжатие данных в архив...${NC}"
if tar -czf "$BACKUP_FILE" "${EXISTING_DIRS[@]}" 2>/dev/null; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | awk '{print $1}')
    log_info "Архив успешно создан: $BACKUP_FILE ($BACKUP_SIZE)"
else
    log_error "Критическая ошибка при создании архива tar!"
    exit 1
fi

find /backup/data -name "data_*.tar.gz" -mtime +7 -delete 2>/dev/null
log_info "Ротация: Локальные архивы старше 7 дней удалены"
log "=========================================="
log "ЛОКАЛЬНЫЙ БЭКАП УСПЕШНО ЗАВЕРШЕН"
log "=========================================="
EOF

chmod +x /usr/local/bin/backup-data.sh
echo -e "${GREEN}[✓]${NC} Скрипт локального бэкапа сохранен: /usr/local/bin/backup-data.sh"

# Прописываем локальный бэкап в cron (по умолчанию — каждый день в 02:00 ночи)
if ! grep -q "backup-data.sh" /etc/crontab 2>/dev/null; then
    cat >> /etc/crontab << 'EOF'
0 2 * * * root /usr/local/bin/backup-data.sh
EOF
    echo -e "${GREEN}[✓]${NC} Задача локального бэкапа внесена в /etc/crontab"
else
    echo -e "${GREEN}[✓]${NC} Локальный бэкап уже активен в планировщике /etc/crontab"
fi

# Выполняем быстрый тестовый локальный сбор данных
echo -e "\n${BLUE}► Запуск тестовой локальной сборки архива...${NC}"
/usr/local/bin/backup-data.sh

# =============================================================================
# ЭТАП 2: УМНОЕ СКАНИРОВАНИЕ И НАСТРОЙКА ОБЛАКА (RCLONE)
# =============================================================================
echo -e "\n${BLUE}[2/2] Анализ конфигурации облачной среды RClone...${NC}"

if ! command -v rclone &>/dev/null; then
    echo -e "${YELLOW}[!] Предупреждение: Программа RClone еще не установлена на этом serer.${NC}"
    echo -e "Сначала установите её, запустив Шаг 5: ${CYAN}sudo ./05-install-services.sh${NC}."
    exit 0
fi

REMOTES=($(rclone listremotes | sed 's/://' || true))
REMOTES_COUNT=${#REMOTES[@]}

RCLONE_TARGET=""

if [ "$REMOTES_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│      РЕСУРСЫ ОБЛАКА НЕ НАСТРОЕНЫ: ЛОКАЛЬНЫЙ БЭКАП ФУНКЦИОНИРУЕТ        │${NC}"
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────────────────┘${NC}"
    echo -e "Локальные архивы будут собираться в папку /backup/data."
    echo -e "Однако выгрузка в облако сейчас не может быть автоматизирована, так как конфиг пуст."
    echo -e "\n${WHITE}Что делать дальше:${NC}"
    echo -e "1) Выполните команду привязки хранилища: ${GREEN}rclone config${NC}"
    echo -e "2) Как только завершите настройку в rclone, ${GREEN}ПОВТОРНО ЗАПУСТИТЕ ЭТОТ СКРИПТ${NC}:"
    echo -e "   Команда: ${WHITE}sudo ./08-backup-setup.sh${NC}"
    exit 0

elif [ "$REMOTES_COUNT" -eq 1 ]; then
    RCLONE_TARGET="${REMOTES}"
    echo -e "${GREEN}[✓]${NC} Найдено активное облако в RClone: ${WHITE}${RCLONE_TARGET}${NC}"

else
    echo -e "${YELLOW}[!] Обнаружено несколько настроенных облаков (${REMOTES_COUNT}):${NC}"
    for i in "${!REMOTES[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${WHITE}${REMOTES[$i]}${NC}"
    done
    echo ""
    while true; do
        read -p "Введите цифру нужного облака для отправки бэкапов: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$REMOTES_COUNT" ]; then
            RCLONE_TARGET="${REMOTES[$((CHOICE-1))]}"
            break
        else
            echo -e "${RED}Ошибка. Введите число от 1 до ${REMOTES_COUNT}${NC}"
        fi
    done
fi

# Создаем скрипт выгрузки с автоматическим подтягиванием HOSTNAME
cat > /usr/local/bin/upload-backup.sh << EOF
#!/bin/bash
set -e

REMOTE_NAME="$RCLONE_TARGET"
# Автоматическое определение имени текущего сервера
SERVER_HOSTNAME=\$(hostname)
REMOTE_PATH="\$REMOTE_NAME:server_backups/\$SERVER_HOSTNAME"
LOG_FILE="/backup/logs/upload_\$(date +%Y%m%d).log"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"; }

BACKUP_FILE=\$(ls -t /backup/data/data_*.tar.gz 2>/dev/null | head -1)

if [ -z "\$BACKUP_FILE" ]; then
    log "⚠️ Ошибка: Файлы бэкапа для отправки не найдены в /backup/data/"
    exit 1
fi

BACKUP_NAME=\$(basename "\$BACKUP_FILE")
BACKUP_SIZE=\$(du -h "\$BACKUP_FILE" | awk '{print \$1}')

log "Старт выгрузки архива в облако [\$REMOTE_PATH]: \$BACKUP_NAME (\$BACKUP_SIZE)"

# Создание персональной папки сервера в облаке
rclone mkdir "\$REMOTE_PATH" 2>/dev/null || true

# Копирование файла в персональную папку
if rclone copy "\$BACKUP_FILE" "\$REMOTE_PATH/"; then
    log "✅ Выгрузка завершена успешно: \$BACKUP_NAME"
    # Очистка в облаке файлов старше 30 дней внутри персональной папки
    rclone delete --min-age 30d "\$REMOTE_PATH/" 2>/dev/null || true
    log "✅ Ротация облака: Старые копии (30+ дней) очищены"
else
    log "❌ КРИТИЧЕСКАЯ ОШИБКА: Не удалось выполнить rclone copy!"
    exit 1
fi
EOF

chmod +x /usr/local/bin/upload-backup.sh
echo -e "${GREEN}[✓]${NC} Скрипт отправки сгенерирован: /usr/local/bin/upload-backup.sh"
echo -e "    Целевой путь в облаке: ${WHITE}${RCLONE_TARGET}:server_backups/$(hostname)/${NC}"

# Прописываем задачу отправки в cron (по умолчанию — каждую ночь в 03:00 ночи)
if ! grep -q "upload-backup.sh" /etc/crontab 2>/dev/null; then
    cat >> /etc/crontab << 'EOF'
# Резервное копирование.
0 3 * * * root /usr/local/bin/upload-backup.sh
EOF
    echo -e "${GREEN}[✓]${NC} Задача отправки в облако внесена в /etc/crontab"
else
    echo -e "${GREEN}[✓]${NC} Задача отправки в облако уже активна в /etc/crontab"
fi

# Выполняем немедленный тест отправки
echo -e "\n${BLUE}► Запуск немедленной тестовой отправки в облако...${NC}"
if /usr/local/bin/upload-backup.sh; then
    echo -e "\n${GREEN}✅ ВСЁ НАСТРОЕНО ОТ И ДО!${NC}"
    echo -e "Имя папки на удаленном диске совпадает с текущим Hostname: ${CYAN}$(hostname)${NC}"
else
    echo -e "\n${RED}[✗] Тестовая отправка не удалась. Убедитесь в валидности токенов rclone.${NC}"
fi
#!/bin/bash
# =============================================================================
# Шаг 8: Настройка локального бэкапа данных и выгрузки в облако RClone
# =============================================================================
# Описание: Создает локальный бэкап и интерактивно привязывает его к облаку.
#           Автоматически сортирует бэкапы в облаке по папкам с Hostname.
# Версия: 2.1 (С привязкой к Hostname сервера)
# =============================================================================

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[✗] Ошибка: Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

echo -e "${CYAN}=====================================================================${NC}"
echo -e "${CYAN}===         НАСТРОЙКА И АВТОМАТИЗАЦИЯ СИСТЕМЫ БЭКАПОВ             ===${NC}"
echo -e "${CYAN}=====================================================================${NC}"

# =============================================================================
# ЭТАП 1: НАСТРОЙКА ЛОКАЛЬНОГО БЭКАПА
# =============================================================================
echo -e "\n${BLUE}[1/2] Проверка локальной структуры папок...${NC}"

mkdir -p /backup/data /backup/logs
echo -e "${GREEN}[✓]${NC} Директории готовы: /backup/data, /backup/logs"

# Создаем скрипт локального архивирования
cat > /usr/local/bin/backup-data.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/backup/data/data_${BACKUP_DATE}.tar.gz"
LOG_FILE="/backup/logs/backup_$(date +%Y%m%d).log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local clean_msg
    clean_msg=$(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${clean_msg}" >> "$LOG_FILE"
}
log_info() { echo -e "${GREEN}[✓]${NC} $1"; log "[✓] $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; log "[!] $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; log "[✗] $1"; }

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
log "НАЧАЛО ЛОКАЛЬНОГО БЭКАПА ДАННЫХ"
log "=========================================="

EXISTING_DIRS=()
for dir in "${DATA_DIRS[@]}"; do
    if [ -e "$dir" ]; then
        EXISTING_DIRS+=("$dir")
        log_info "Найден каталог: $dir"
    else
        log_warn "Пропущен (отсутствует): $dir"
    fi
done

if [ ${#EXISTING_DIRS[@]} -eq 0 ]; then
    log_error "Критическая ошибка: Нет доступных данных для архивации!"
    exit 1
fi

echo -e "${YELLOW}[...] Сжатие данных в архив...${NC}"
if tar -czf "$BACKUP_FILE" "${EXISTING_DIRS[@]}" 2>/dev/null; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | awk '{print $1}')
    log_info "Архив успешно создан: $BACKUP_FILE ($BACKUP_SIZE)"
else
    log_error "Критическая ошибка при создании архива tar!"
    exit 1
fi

find /backup/data -name "data_*.tar.gz" -mtime +7 -delete 2>/dev/null
log_info "Ротация: Локальные архивы старше 7 дней удалены"
log "=========================================="
log "ЛОКАЛЬНЫЙ БЭКАП УСПЕШНО ЗАВЕРШЕН"
log "=========================================="
EOF

chmod +x /usr/local/bin/backup-data.sh
echo -e "${GREEN}[✓]${NC} Скрипт локального бэкапа сохранен: /usr/local/bin/backup-data.sh"

# Прописываем локальный бэкап в cron (по умолчанию — каждый день в 02:00 ночи)
if ! grep -q "backup-data.sh" /etc/crontab 2>/dev/null; then
    cat >> /etc/crontab << 'EOF'
0 2 * * * root /usr/local/bin/backup-data.sh
EOF
    echo -e "${GREEN}[✓]${NC} Задача локального бэкапа внесена в /etc/crontab"
else
    echo -e "${GREEN}[✓]${NC} Локальный бэкап уже активен в планировщике /etc/crontab"
fi

# Выполняем быстрый тестовый локальный сбор данных
echo -e "\n${BLUE}► Запуск тестовой локальной сборки архива...${NC}"
/usr/local/bin/backup-data.sh

# =============================================================================
# ЭТАП 2: УМНОЕ СКАНИРОВАНИЕ И НАСТРОЙКА ОБЛАКА (RCLONE)
# =============================================================================
echo -e "\n${BLUE}[2/2] Анализ конфигурации облачной среды RClone...${NC}"

if ! command -v rclone &>/dev/null; then
    echo -e "${YELLOW}[!] Предупреждение: Программа RClone еще не установлена на этом serer.${NC}"
    echo -e "Сначала установите её, запустив Шаг 5: ${CYAN}sudo ./05-install-services.sh${NC}."
    exit 0
fi

REMOTES=($(rclone listremotes | sed 's/://' || true))
REMOTES_COUNT=${#REMOTES[@]}

RCLONE_TARGET=""

if [ "$REMOTES_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│      РЕСУРСЫ ОБЛАКА НЕ НАСТРОЕНЫ: ЛОКАЛЬНЫЙ БЭКАП ФУНКЦИОНИРУЕТ        │${NC}"
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────────────────┘${NC}"
    echo -e "Локальные архивы будут собираться в папку /backup/data."
    echo -e "Однако выгрузка в облако сейчас не может быть автоматизирована, так как конфиг пуст."
    echo -e "\n${WHITE}Что делать дальше:${NC}"
    echo -e "1) Выполните команду привязки хранилища: ${GREEN}rclone config${NC}"
    echo -e "2) Как только завершите настройку в rclone, ${GREEN}ПОВТОРНО ЗАПУСТИТЕ ЭТОТ СКРИПТ${NC}:"
    echo -e "   Команда: ${WHITE}sudo ./08-backup-setup.sh${NC}"
    exit 0

elif [ "$REMOTES_COUNT" -eq 1 ]; then
    RCLONE_TARGET="${REMOTES}"
    echo -e "${GREEN}[✓]${NC} Найдено активное облако в RClone: ${WHITE}${RCLONE_TARGET}${NC}"

else
    echo -e "${YELLOW}[!] Обнаружено несколько настроенных облаков (${REMOTES_COUNT}):${NC}"
    for i in "${!REMOTES[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${WHITE}${REMOTES[$i]}${NC}"
    done
    echo ""
    while true; do
        read -p "Введите цифру нужного облака для отправки бэкапов: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$REMOTES_COUNT" ]; then
            RCLONE_TARGET="${REMOTES[$((CHOICE-1))]}"
            break
        else
            echo -e "${RED}Ошибка. Введите число от 1 до ${REMOTES_COUNT}${NC}"
        fi
    done
fi

# Создаем скрипт выгрузки с автоматическим подтягиванием HOSTNAME
cat > /usr/local/bin/upload-backup.sh << EOF
#!/bin/bash
set -e

REMOTE_NAME="$RCLONE_TARGET"
# Автоматическое определение имени текущего сервера
SERVER_HOSTNAME=\$(hostname)
REMOTE_PATH="\$REMOTE_NAME:server_backups/\$SERVER_HOSTNAME"
LOG_FILE="/backup/logs/upload_\$(date +%Y%m%d).log"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"; }

BACKUP_FILE=\$(ls -t /backup/data/data_*.tar.gz 2>/dev/null | head -1)

if [ -z "\$BACKUP_FILE" ]; then
    log "⚠️ Ошибка: Файлы бэкапа для отправки не найдены в /backup/data/"
    exit 1
fi

BACKUP_NAME=\$(basename "\$BACKUP_FILE")
BACKUP_SIZE=\$(du -h "\$BACKUP_FILE" | awk '{print \$1}')

log "Старт выгрузки архива в облако [\$REMOTE_PATH]: \$BACKUP_NAME (\$BACKUP_SIZE)"

# Создание персональной папки сервера в облаке
rclone mkdir "\$REMOTE_PATH" 2>/dev/null || true

# Копирование файла в персональную папку
if rclone copy "\$BACKUP_FILE" "\$REMOTE_PATH/"; then
    log "✅ Выгрузка завершена успешно: \$BACKUP_NAME"
    # Очистка в облаке файлов старше 30 дней внутри персональной папки
    rclone delete --min-age 30d "\$REMOTE_PATH/" 2>/dev/null || true
    log "✅ Ротация облака: Старые копии (30+ дней) очищены"
else
    log "❌ КРИТИЧЕСКАЯ ОШИБКА: Не удалось выполнить rclone copy!"
    exit 1
fi
EOF

chmod +x /usr/local/bin/upload-backup.sh
echo -e "${GREEN}[✓]${NC} Скрипт отправки сгенерирован: /usr/local/bin/upload-backup.sh"
echo -e "    Целевой путь в облаке: ${WHITE}${RCLONE_TARGET}:server_backups/$(hostname)/${NC}"

# Прописываем задачу отправки в cron (по умолчанию — каждую ночь в 03:00 ночи)
if ! grep -q "upload-backup.sh" /etc/crontab 2>/dev/null; then
    cat >> /etc/crontab << 'EOF'
# Резервное копирование.
0 3 * * * root /usr/local/bin/upload-backup.sh
EOF
    echo -e "${GREEN}[✓]${NC} Задача отправки в облако внесена в /etc/crontab"
else
    echo -e "${GREEN}[✓]${NC} Задача отправки в облако уже активна в /etc/crontab"
fi

# Выполняем немедленный тест отправки
echo -e "\n${BLUE}► Запуск немедленной тестовой отправки в облако...${NC}"
if /usr/local/bin/upload-backup.sh; then
    echo -e "\n${GREEN}✅ ВСЁ НАСТРОЕНО ОТ И ДО!${NC}"
    echo -e "Имя папки на удаленном диске совпадает с текущим Hostname: ${CYAN}$(hostname)${NC}"
else
    echo -e "\n${RED}[✗] Тестовая отправка не удалась. Убедитесь в валидности токенов rclone.${NC}"
fi
