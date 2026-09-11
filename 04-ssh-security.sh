#!/bin/bash
# =============================================================================
# Debian 13 Server - Настройка SSH, UFW, fail2ban
# =============================================================================
# Описание: Создание пользователя, настройка SSH, UFW, fail2ban
# Версия: 1.1 (Исправленная динамическая сборка)
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
    log_error "Запустите с правами root: sudo ./04-ssh-security.sh"
    exit 1
fi

# =============================================================================
# ЗАГРУЗКА КОНФИГУРАЦИИ
# =============================================================================
BACKUP_DIR=$(ls -td /root/backup_* 2>/dev/null | head -1)
if [ -z "$BACKUP_DIR" ]; then
    log_error "Не найдена директория с бэкапами"
    exit 1
fi

source "$BACKUP_DIR/system_config.conf" 2>/dev/null || true
LOG_FILE="$BACKUP_DIR/ssh_setup.log"

# =============================================================================
# РАЗДЕЛ 1: ВВОД ДАННЫХ
# =============================================================================
log_step "Раздел 1: Ввод данных"

read -p "Введите имя нового пользователя [vasa]: " USERNAME
USERNAME=${USERNAME:-vasa}

read -p "Введите порт SSH (по умолчанию: 27244): " NEW_SSH_PORT
NEW_SSH_PORT=${NEW_SSH_PORT:-27244}

# =============================================================================
# РАЗДЕЛ 2: СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
# =============================================================================
log_step "Раздел 2: Создание пользователя"

if id "$USERNAME" &>/dev/null; then
    log_warn "Пользователь $USERNAME уже существует"
    read -p "Использовать существующего для настройки? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "Введите другое имя: " USERNAME
        useradd -m -G sudo -s /bin/bash "$USERNAME"
    else
        usermod -aG sudo "$USERNAME"
    fi
else
    useradd -m -G sudo -s /bin/bash "$USERNAME"
    log_success "Пользователь $USERNAME создан"
fi

echo -e "\n${YELLOW}Установка пароля для $USERNAME:${NC}"
passwd "$USERNAME"

# =============================================================================
# РАЗДЕЛ 3: НАСТРОЙКА SSH КЛЮЧЕЙ
# =============================================================================
log_step "Раздел 3: Настройка SSH ключей"

SSH_DIR="/home/$USERNAME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"

echo -e "${YELLOW}Добавление SSH ключа:${NC}"
echo "1) Передать публичный ключ на лету (Вставить строку из Windows)"
echo "2) Сгенерировать новый ключ прямо на сервере"
echo "3) Пропустить"
read -p "Выберите вариант (1/2/3): " CHOICE

case "$CHOICE" in
    1)
        echo -e "\n${CYAN}Выведите публичный ключ на Windows командой:${NC} type %USERPROFILE%\.ssh\id_ed25519.pub"
        echo -e "${YELLOW}Вставьте строку публичного ключа и нажмите Enter:${NC}"
        read -r INPUT_SSH_KEY
        
        # Очищаем строку от скрытых DOS/Windows символов переноса строк \r\n
        CLEAN_SSH_KEY=$(echo "$INPUT_SSH_KEY" | tr -d '\r\n')
        
        if [ ! -z "$CLEAN_SSH_KEY" ]; then
            echo "$CLEAN_SSH_KEY" > "$AUTH_KEYS"
            log_success "Ключ успешно импортирован на лету для пользователя $USERNAME"
        else
            log_error "Ключ не введен. Файл authorized_keys пуст!"
        fi
        ;;
    2)
        sudo -u "$USERNAME" ssh-keygen -t ed25519 -C "$USERNAME@$(hostname)" -N "" -f "$SSH_DIR/id_ed25519"
        PUBLIC_KEY=$(sudo -u "$USERNAME" cat "$SSH_DIR/id_ed25519.pub")
        echo "$PUBLIC_KEY" > "$AUTH_KEYS"
        log_success "Ключ сгенерирован"
        echo -e "${YELLOW}Публичный ключ сервера (сохраните себе на ПК):${NC}"
        echo "$PUBLIC_KEY"
        ;;
    3)
        log_warn "Настройка SSH ключей пропущена"
        ;;
    *)
        log_error "Неверный выбор"
        ;;
esac

# Фиксируем жесткие безопасные права на папки в соответствии с владельцем
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
[ -f "$AUTH_KEYS" ] && chmod 600 "$AUTH_KEYS"

# =============================================================================
# РАЗДЕЛ 4: НАСТРОЙКА SSH СЕРВЕРА (ДИНАМИЧЕСКИЙ ВВОД)
# =============================================================================
log_step "Раздел 4: Настройка SSH сервера"

log_info "Генерация динамической конфигурации /etc/ssh/sshd_config.d/00-custom.conf..."

# Кавычки с EOF сняты! Переменные $NEW_SSH_PORT и $USERNAME подставятся динамически!
cat > /etc/ssh/sshd_config.d/00-custom.conf << EOF
# Кастомные настройки SSH
# Создано автоматически: $(date '+%Y-%m-%d %H:%M:%S')

# Применяем кастомный порт из конфигурации
Port $NEW_SSH_PORT

# Блокируем авторизацию под суперпользователем root
PermitRootLogin no

# Разрешаем подключения по криптографическим ключам
PubkeyAuthentication yes

# Полностью отключаем вход по текстовым паролям
PasswordAuthentication no

# Ограничиваем доступ только выбранному администратору
AllowUsers $USERNAME

# Параметры защиты сессий от зависания
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 3
MaxSessions 10
TCPKeepAlive yes
EOF

log_success "Конфигурация SSH создана успешно"

# Проверка конфигурации на синтаксис перед перезапуском
if sshd -t 2>/dev/null; then
    log_success "Конфигурация SSH проверена успешно"
else
    log_error "Ошибка в конфигурации SSH! Откат изменений."
    rm -f /etc/ssh/sshd_config.d/00-custom.conf
    exit 1
fi

# Перезапуск службы SSH
systemctl restart ssh
sleep 2

# Проверка порта
if ss -tlnp | grep -q ":$NEW_SSH_PORT"; then
    log_success "SSH перезапущен на порту $NEW_SSH_PORT"
else
    log_error "SSH не запущен на порту $NEW_SSH_PORT"
    ss -tlnp | grep ssh
fi

# =============================================================================
# РАЗДЕЛ 5: НАСТРОЙКА UFW
# =============================================================================
log_step "Раздел 5: Настройка UFW"

ufw allow "$NEW_SSH_PORT"/tcp
log_info "Разрешен порт $NEW_SSH_PORT"

if [ "$NEW_SSH_PORT" != "22" ]; then
    ufw allow 22/tcp
    log_warn "Порт 22 временно разрешен для предотвращения блокировки"
fi

ufw --force enable
systemctl restart ufw
ufw status verbose

# =============================================================================
# РАЗДЕЛ 6: НАСТРОЙКА FAIL2BAN
# =============================================================================
log_step "Раздел 6: Настройка fail2ban"

if command -v fail2ban &>/dev/null; then
    # Переменная $NEW_SSH_PORT подставится динамически
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8

bantime = 1h
findtime = 10m
maxretry = 5
banaction = nftables-multiport
action = %(action_)s

[sshd]
enabled = true
port = $NEW_SSH_PORT
logpath = %(sshd_log)s
backend = systemd
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    sleep 2

    if systemctl is-active --quiet fail2ban; then
        log_success "fail2ban активен"
    else
        log_error "fail2ban не запустился"
    fi
else
    log_error "fail2ban не установлен"
fi

# =============================================================================
# РАЗДЕЛ 7: СИСТЕМНЫЕ НАСТРОЙКИ
# =============================================================================
log_step "Раздел 7: Системные настройки"

if [ ! -f /swap ]; then
    log_info "Создание SWAP файла размером 1GB..."
    fallocate -l 1G /swap
    chmod 600 /swap
    mkswap /swap
    swapon /swap
    
    if ! grep -q "/swap" /etc/fstab; then
        echo "/swap    none    swap    sw    0    0" >> /etc/fstab
    fi
    log_success "SWAP создан"
fi

log_info "Настройка локалей..."
apt install -y locales
dpkg-reconfigure locales

log_info "Установка часового пояса..."
timedatectl set-timezone Asia/Yekaterinburg

log_info "Настройка ротации логов системного журнала..."
if ! grep -q "SystemMaxUse=800M" /etc/systemd/journald.conf; then
    cat >> /etc/systemd/journald.conf << 'EOF'
[Journal]
SystemMaxUse=800M
MaxFileSec=2week
EOF
fi
systemctl restart systemd-journald
journalctl --vacuum-size=800M 2>/dev/null || true

# =============================================================================
# РАЗДЕЛ 8: ЗАКРЫТИЕ 22 ПОРТА
# =============================================================================
log_step "Раздел 8: Закрытие порта 22 (опционально)"

echo -e "${YELLOW}⚠️  ВНИМАНИЕ:${NC}"
echo "Перед закрытием порта 22 убедитесь, что новая сессия по ключу работает!"
echo ""
echo -e "${CYAN}Проверьте подключение в новой вкладке вашего терминала:${NC}"
echo -e "  ssh -p $NEW_SSH_PORT $USERNAME@\$(ip route get 1.1.1.1 2>/dev/null | awk '{print \$7}')"
echo ""

read -p "Закрыть порт 22 в фаерволе UFW прямо сейчас? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ufw delete allow 22/tcp
    ufw reload
    log_success "Порт 22 успешно закрыт"
else
    log_warn "Порт 22 оставлен открытым для контроля"
fi

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ (ПРАВИЛЬНЫЙ ВАРИАНТ)
# =============================================================================
log_step "Настройка SSH и безопасности завершена"

# Экранируем знак $, чтобы команда выполнилась внутри созданного скрипта
HOST_IP=\$(ip route get 1.1.1.1 2>/dev/null | awk '{print \$7}' || echo "<IP_АДРЕС>")

echo -e "\${GREEN}✅ SSH и конфигурация безопасности успешно применены!\${NC}"
echo ""
echo -e "\${YELLOW}📋 Информация для подключения:\${NC}"
# Добавлен обратный слеш \$ перед переменными:
echo "  Пользователь: \$USERNAME"
echo "  Новый порт:   \$NEW_SSH_PORT"
echo "  IP адрес vps: \$HOST_IP"
echo ""
echo -e "\${CYAN}Команда для входа:\${NC}"
echo -e "\${WHITE}  ssh \$USERNAME@\$HOST_IP -p \$NEW_SSH_PORT\${NC}"
echo ""

read -p "Выполнить финальную перезагрузку сервера для применения всех параметров? (y/N): " -n 1 -r
echo ""
if [[ \$REPLY =~ ^[Yy]$ ]]; then
    log_warn "Сервер уходит в перезагрузку..."
    reboot
fi
