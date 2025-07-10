#!/bin/bash

# Цвета для красоты
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Анимация спиннера
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Проверка на root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}✗ Запустите скрипт от root: sudo bash $0${NC}" >&2
    exit 1
fi

# Генерация случайного SSH-порта (10000-65300)
NEW_SSH_PORT=$(shuf -i 10000-65300 -n 1)

# Настройка SSH
echo -e "${BLUE}🔹 Меняем SSH-порт на $NEW_SSH_PORT...${NC}"
sed -i "s/^#\?Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
(systemctl restart sshd) & spinner $!
echo -e "\n${GREEN}✓ SSH настроен!${NC}"

# Настройка UFW
echo -e "${BLUE}🔹 Настраиваем фаервол...${NC}"
(apt update && apt install -y ufw) & spinner $!
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$NEW_SSH_PORT/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 54321/tcp
(ufw --force enable) & spinner $!
echo -e "\n${GREEN}✓ Фаервол настроен!${NC}"

# Установка Docker
echo -e "${BLUE}🔹 Устанавливаем Docker...${NC}"
(apt install -y docker.io docker-compose) & spinner $!
(systemctl enable docker --now) & spinner $!
echo -e "\n${GREEN}✓ Docker установлен!${NC}"

# Установка 3XUI
echo -e "${BLUE}🔹 Устанавливаем 3XUI...${NC}"
(bash <(curl -Ls https://raw.githubusercontent.com/3x-ui/3x-ui/master/install.sh)) & spinner $!
echo -e "\n${GREEN}✓ 3XUI установлен!${NC}"

# Создание пользователя
USERNAME="xuiadmin$(shuf -i 1000-9999 -n 1)"
read -rp "$(echo -e ${YELLOW}"Введите имя пользователя (или Enter для '$USERNAME'): "${NC})" CUSTOM_USER
[ -n "$CUSTOM_USER" ] && USERNAME="$CUSTOM_USER"

if id "$USERNAME" &>/dev/null; then
    echo -e "${YELLOW}⚠ Пользователь $USERNAME уже существует. Пропускаем.${NC}"
else
    (useradd -m -s /bin/bash "$USERNAME") & spinner $!
    echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
    PASS=$(openssl rand -base64 12)
    echo "$USERNAME:$PASS" | chpasswd
    echo -e "${GREEN}✓ Пользователь $USERNAME создан.${NC}"
    echo -e "${YELLOW}🔑 Пароль: $PASS${NC}"
fi

# Вывод итогов
echo -e "\n${GREEN}✅ Настройка завершена!${NC}"
echo -e "${BLUE}🔹 SSH-порт: $NEW_SSH_PORT${NC}"
echo -e "${BLUE}🔹 3XUI: http://$(curl -s ifconfig.me):54321${NC}"
echo -e "${YELLOW}🔹 Логин/пароль 3XUI: admin / admin (смените после входа!)${NC}"

# ASCII-арт "CHAI"
echo -e "${RED}
  ____ _           _ 
 / ___| |__   __ _(_)
| |   | '_ \ / _` | |
| |___| | | | (_| | |
 \____|_| |_|\__,_|_|
${NC}"
