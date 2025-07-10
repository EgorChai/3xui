#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка на root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}✗ Ошибка: Скрипт должен запускаться от root! Используйте:${NC}"
    echo -e "sudo bash $0"
    exit 1
fi

# Функция для безопасной работы с apt
safe_apt() {
    echo -e "${BLUE}🔹 Выполняем: apt $@${NC}"
    
    # Ожидаем освобождения блокировки (максимум 2 минуты)
    timeout 120 bash -c "
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            echo -e '${YELLOW}⚠ Ожидаем освобождения блокировки apt...${NC}'
            sleep 10
        done"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Не удалось получить блокировку apt!${NC}"
        echo -e "${YELLOW}Попробуйте выполнить вручную: sudo rm -f /var/lib/dpkg/lock-frontend${NC}"
        exit 1
    fi
    
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 -yq "$@"
}

# 1. Первоначальная настройка сервера
echo -e "${GREEN}=== НАСТРОЙКА НОВОГО СЕРВЕРА UBUNTU 22.04 ===${NC}"

# Обновление пакетов (первый этап)
echo -e "${BLUE}🔹 Обновление списка пакетов...${NC}"
safe_apt update

# Обновление системы (второй этап)
echo -e "${BLUE}🔹 Обновление установленных пакетов...${NC}"
safe_apt upgrade

# Установка базовых утилит
echo -e "${BLUE}🔹 Установка базовых утилит...${NC}"
safe_apt install -y \
    curl \
    wget \
    git \
    ufw \
    htop \
    nano \
    net-tools \
    gnupg2 \
    ca-certificates \
    software-properties-common

# 2. Настройка SSH
NEW_SSH_PORT=$(shuf -i 10000-65300 -n 1)
echo -e "${BLUE}🔹 Меняем SSH-порт на $NEW_SSH_PORT...${NC}"

# Резервное копирование конфига SSH
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Изменение порта
sed -i "s/^#\?Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config

# Дополнительные настройки безопасности SSH
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config

systemctl restart sshd
echo -e "${GREEN}✓ SSH настроен! Порт: $NEW_SSH_PORT${NC}"

# 3. Настройка фаервола
echo -e "${BLUE}🔹 Настройка UFW...${NC}"

# Сброс правил
ufw --force reset

# Базовые настройки
ufw default deny incoming
ufw default allow outgoing

# Разрешаем нужные порты
ufw allow $NEW_SSH_PORT/tcp comment 'SSH Custom Port'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 54321/tcp comment '3XUI Panel'

# Включаем фаервол
ufw --force enable
echo -e "${GREEN}✓ Фаервол настроен!${NC}"

# 4. Установка Docker
echo -e "${BLUE}🔹 Установка Docker...${NC}"

# Официальный метод установки Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

safe_apt update
safe_apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker --now
echo -e "${GREEN}✓ Docker установлен!${NC}"

# 5. Установка 3XUI
echo -e "${BLUE}🔹 Установка 3XUI...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
echo -e "${GREEN}✓ 3XUI установлен!${NC}"

# 6. Создание пользователя
echo -e "${BLUE}🔹 Создание системного пользователя...${NC}"

USERNAME="xuiadmin$(shuf -i 1000-9999 -n 1)"
read -rp "$(echo -e ${YELLOW}"Введите имя пользователя (или Enter для '$USERNAME'): "${NC})" CUSTOM_USER
[ -n "$CUSTOM_USER" ] && USERNAME="$CUSTOM_USER"

if ! id "$USERNAME" &>/dev/null; then
    # Создаем пользователя
    useradd -m -s /bin/bash "$USERNAME"
    
    # Добавляем в sudo без пароля
    echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    # Генерируем сложный пароль
    PASS=$(openssl rand -base64 16 | tr -d '/+' | head -c 16)
    echo "$USERNAME:$PASS" | chpasswd
    
    # Настраиваем базовое окружение
    [ -d "/home/$USERNAME/.ssh" ] || mkdir -p "/home/$USERNAME/.ssh"
    chmod 700 "/home/$USERNAME/.ssh"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
    
    echo -e "${GREEN}✓ Пользователь $USERNAME создан${NC}"
    echo -e "${YELLOW}🔑 Пароль: $PASS${NC}"
    echo -e "${YELLOW}⚠ Обязательно сохраните этот пароль!${NC}"
else
    echo -e "${YELLOW}⚠ Пользователь $USERNAME уже существует${NC}"
fi

# 7. Финишная настройка
echo -e "${BLUE}🔹 Финальная настройка...${NC}"

# Включаем автоматические обновления безопасности
safe_apt install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# Очистка кеша apt
safe_apt autoremove -y
safe_apt clean

# 8. Вывод результатов
echo -e "\n${GREEN}✅ НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}🔹 SSH доступ:${NC}"
echo -e "Порт: $NEW_SSH_PORT"
echo -e "Рекомендуем: ssh -p $NEW_SSH_PORT ваш_пользователь@ip_сервера"
echo -e "${YELLOW}🔹 3XUI Панель:${NC}"
echo -e "URL: http://$(curl -s ifconfig.me):54321"
echo -e "Логин: admin"
echo -e "Пароль: admin"
echo -e "${YELLOW}🔹 Создан пользователь:${NC}"
echo -e "Имя: $USERNAME"
echo -e "Пароль: $PASS"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}⚠ Рекомендуется:${NC}"
echo -e "1. Сменить пароль в панели 3XUI"
echo -e "2. Добавить SSH-ключ для пользователя"
echo -e "3. Перезагрузить сервер (команда: reboot)"

# ASCII логотип
echo -e "${RED}
  ____   _    _   _   _ 
 / ___| | |  | | | | | |
| |     | |  | | | | | |
| |___  | |__| | | |_| |
 \____|  \____/   \___/ 
${NC}"
