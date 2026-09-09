#!/bin/bash
# =============================================================================
# Debian 13 Server - Настройка SSH, UFW, fail2ban
# =============================================================================
# Описание: Создание пользователя, настройка SSH, UFW, fail2ban
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

read -p "Введите имя нового пользователя: " USERNAME
if [ -z "$USERNAME" ]; then
    log_error "Имя пользователя не может быть пустым"
    exit 1
fi

read -p "Введите порт SSH (по умолчанию: 27244): " NEW_SSH_PORT
NEW_SSH_PORT=${NEW_SSH_PORT:-27244}

# =============================================================================
# РАЗДЕЛ 2: СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
# =============================================================================
log_step "Раздел 2: Создание пользователя"

if id "$USERNAME" &>/dev/null; then
    log_warn "Пользователь $USERNAME уже существует"
    read -p "Использовать существующего? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "Введите другое имя: " USERNAME
        useradd -m -G sudo -s /bin/bash "$USERNAME"
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
chown "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"

echo -e "${YELLOW}Добавление SSH ключа:${NC}"
echo "1) Вставить публичный ключ вручную"
echo "2) Сгенерировать новый ключ"
echo "3) Пропустить"
read -p "Выберите вариант (1/2/3): " CHOICE

case "$CHOICE" in
    1)
        echo -e "\n${YELLOW}Вставьте публичный SSH ключ и нажмите Ctrl+D:${NC}"
        cat >> "$AUTH_KEYS"
        chown "$USERNAME:$USERNAME" "$AUTH_KEYS"
        chmod 600 "$AUTH_KEYS"
        log_success "Ключ добавлен"
        ;;
    2)
        sudo -u "$USERNAME" ssh-keygen -t ed25519 -C "$USERNAME@$(hostname)"
        PUBLIC_KEY=$(sudo -u "$USERNAME" cat "/home/$USERNAME/.ssh/id_ed25519.pub")
        echo "$PUBLIC_KEY" >> "$AUTH_KEYS"
        chown "$USERNAME:$USERNAME" "$AUTH_KEYS"
        chmod 600 "$AUTH_KEYS"
        log_success "Ключ сгенерирован"
        echo -e "${YELLOW}Публичный ключ:${NC}"
        echo "$PUBLIC_KEY"
        ;;
    3)
        log_warn "Настройка SSH ключей пропущена"
        ;;
    *)
        log_error "Неверный выбор"
        ;;
esac

# =============================================================================
# РАЗДЕЛ 4: НАСТРОЙКА SSH СЕРВЕРА
# =============================================================================
log_step "Раздел 4: Настройка SSH сервера"

# Создание конфигурации
cat > /etc/ssh/sshd_config.d/00-custom.conf << EOF
# Кастомные настройки SSH
# Создано: $(date '+%Y-%m-%d %H:%M:%S')

# Меняем стандартный порт подключения
Port $NEW_SSH_PORT

# Отключаем возможность подключаться под пользователем root
PermitRootLogin no

# Явно разрешаем подключения по ключу
PubkeyAuthentication yes

# Отключаем подключения по паролю
PasswordAuthentication no

# Разрешаем подключение только указанным пользователям
AllowUsers $USERNAME

# Дополнительные настройки безопасности
ClientAliveInterval 60
ClientAliveCountMax 3
MaxAuthTries 3
MaxSessions 10
TCPKeepAlive yes
EOF

log_success "Конфигурация SSH создана"

# Проверка конфигурации
if sshd -t 2>/dev/null; then
    log_success "Конфигурация SSH проверена успешно"
else
    log_error "Ошибка в конфигурации SSH!"
    sshd -t
    exit 1
fi

# Перезапуск SSH
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

# Разрешаем SSH порт
ufw allow "$NEW_SSH_PORT"/tcp
log_info "Разрешен порт $NEW_SSH_PORT"

# Если порт отличается от 22, разрешаем 22 для восстановления
if [ "$NEW_SSH_PORT" != "22" ]; then
    ufw allow 22/tcp
    log_warn "Порт 22 разрешен для восстановления доступа"
fi

# Включаем фаервол
ufw --force enable
systemctl restart ufw

ufw status verbose

# =============================================================================
# РАЗДЕЛ 6: НАСТРОЙКА FAIL2BAN
# =============================================================================
log_step "Раздел 6: Настройка fail2ban"

if command -v fail2ban &>/dev/null; then
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Добавьте сюда через пробел ваш личный домашний или рабочий IP
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
        fail2ban-client status
        fail2ban-client status sshd
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

# Настройка SWAP
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

# Настройка локалей
log_info "Настройка локалей..."
apt install -y locales

log_warn "Настройка локалей (интерактивный режим)..."
log_warn "Выберите: ru_RU.UTF-8 и en_US.UTF-8"
sleep 3
dpkg-reconfigure locales

# Часовой пояс
log_info "Установка часового пояса..."
timedatectl set-timezone Asia/Yekaterinburg

# Ротация логов
log_info "Настройка ротации логов..."
if ! grep -q "SystemMaxUse=800M" /etc/systemd/journald.conf; then
    cat >> /etc/systemd/journald.conf << 'EOF'
[Journal]
SystemMaxUse=800M
MaxFileSec=2week
EOF
fi
systemctl restart systemd-journald

# Очистка старых логов
journalctl --vacuum-size=800M 2>/dev/null || true

# =============================================================================
# РАЗДЕЛ 8: ЗАКРЫТИЕ 22 ПОРТА
# =============================================================================
log_step "Раздел 8: Закрытие порта 22 (опционально)"

echo -e "${YELLOW}⚠️  ВНИМАНИЕ:${NC}"
echo "Сейчас вы подключены по SSH на порту 22"
echo "Перед закрытием порта 22 убедитесь, что новое подключение работает:"
echo ""
echo -e "${CYAN}Проверьте подключение в новой сессии:${NC}"
echo -e "ssh -p $NEW_SSH_PORT $USERNAME@$(ip addr show | grep -E "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)"
echo ""

read -p "Закрыть порт 22 в UFW? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ufw delete allow 22/tcp
    ufw reload
    log_success "Порт 22 закрыт"
else
    log_warn "Порт 22 оставлен открытым"
fi

# =============================================================================
# ИТОГОВЫЙ ОТЧЕТ
# =============================================================================
log_step "Настройка SSH и безопасности завершена"

HOST_IP=$(ip addr show | grep -E "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)

echo -e "${GREEN}✅${NC} SSH и безопасность настроены!"
echo ""
echo -e "${YELLOW}📋 Информация для подключения:${NC}"
echo "  Пользователь: $USERNAME"
echo "  Порт: $NEW_SSH_PORT"
echo "  IP адрес: ${HOST_IP:-не определен}"
echo ""
echo -e "${CYAN}Команда для подключения:${NC}"
echo -e "${WHITE}ssh -p $NEW_SSH_PORT $USERNAME@${HOST_IP:-<IP_АДРЕС>}${NC}"
echo ""
echo -e "${YELLOW}⚠️  ВАЖНО:${NC}"
echo "  • Проверьте подключение в новой сессии!"
echo "  • Сохраните свой SSH ключ в безопасном месте"
echo "  • Если порт 22 закрыт, восстановление только через консоль VPS"
echo ""
echo -e "${CYAN}📁 Бэкапы:${NC} $BACKUP_DIR"
echo -e "${CYAN}📄 Лог:${NC} $LOG_FILE"

read -p "Перезагрузить сервер? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_warn "Перезагрузка..."
    reboot
fi
