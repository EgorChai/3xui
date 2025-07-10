#!/bin/bash

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для безопасной установки пакетов
safe_apt() {
    echo -e "${BLUE}🔹 Проверяем блокировки apt...${NC}"
    
    # Ожидаем освобождения блокировки (максимум 5 минут)
    timeout 300 bash -c "
        while [ -f /var/lib/dpkg/lock-frontend ]; do
            echo -e '${YELLOW}⚠ Ожидаем освобождения блокировки apt...${NC}'
            sleep 10
        done"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Не удалось получить блокировку apt!${NC}"
        echo -e "${YELLOW}Попробуйте выполнить вручную: sudo rm -f /var/lib/dpkg/lock-frontend${NC}"
        exit 1
    fi
    
    apt-get -o DPkg::Lock::Timeout=60 "$@"
}

# Проверка root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}✗ Запустите скрипт от root: sudo bash $0${NC}" >&2
    exit 1
fi

# Генерация SSH-порта (10000-65300)
NEW_SSH_PORT=$(shuf -i 10000-65300 -n 1)

# Меняем SSH-порт
echo -e "${BLUE}🔹 Меняем SSH-порт на $NEW_SSH_PORT...${NC}"
sed -i "s/^#\?Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
systemctl restart sshd
echo -e "${GREEN}✓ SSH настроен!${NC}"

# Настройка UFW
echo -e "${BLUE}🔹 Настраиваем фаервол...${NC}"
safe_apt update
safe_apt install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$NEW_SSH_PORT/tcp"
ufw allow 80,443,54321/tcp
ufw --force enable
echo -e "${GREEN}✓ Фаервол настроен!${NC}"

# Установка Docker
echo -e "${BLUE}🔹 Устанавливаем Docker...${NC}"
safe_apt install -y docker.io docker-compose
systemctl enable docker --now
echo -e "${GREEN}✓ Docker установлен!${NC}"

# Установка 3XUI
echo -e "${BLUE}🔹 Устанавливаем 3XUI...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
echo -e "${GREEN}✓ 3XUI установлен!${NC}"

# Создание пользователя
USERNAME="xuiadmin$(shuf -i 1000-9999 -n 1)"
read -rp "$(echo -e ${YELLOW}"Введите имя пользователя (или Enter для '$USERNAME'): "${NC})" CUSTOM_USER
[ -n "$CUSTOM_USER" ] && USERNAME="$CUSTOM_USER"

if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
    PASS=$(openssl rand -base64 12)
    echo "$USERNAME:$PASS" | chpasswd
    echo -e "${GREEN}✓ Пользователь $USERNAME создан.${NC}"
    echo -e "${YELLOW}🔑 Пароль: $PASS${NC}"
else
    echo -e "${YELLOW}⚠ Пользователь $USERNAME уже существует. Пропускаем.${NC}"
fi

# Итоги
echo -e "\n${GREEN}✅ Настройка завершена!${NC}"
echo -e "${BLUE}🔹 SSH-порт: $NEW_SSH_PORT${NC}"
echo -e "${BLUE}🔹 3XUI: http://$(curl -s ifconfig.me):54321${NC}"
echo -e "${YELLOW}🔹 Логин/пароль 3XUI: admin / admin (смените после входа!)${NC}"

# ASCII-арт "CHAI"
echo -e "${RED}
  ____   _    _   _   _ 
 / ___| | |  | | | | | |
| |     | |  | | | | | |
| |___  | |__| | | |_| |
 \____|  \____/   \___/ 
${NC}"
