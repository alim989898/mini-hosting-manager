#!/bin/bash

set -e

ACTION=$1
DOMAIN=$2
FTPPASS=$3

APACHE_SITES="/etc/apache2/sites-available"
WEB_ROOT="/var/www"

install_stack() {
    echo "▶ Установка Apache, PHP, MySQL, FTP, SSL..."
    apt update
    apt install -y apache2 mysql-server php libapache2-mod-php \
        php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip \
        vsftpd certbot python3-certbot-apache ufw
    
    # Настройка брандмауэра
    ufw allow 22
    ufw allow 80
    ufw allow 443
    ufw allow 21
    ufw --force enable

    systemctl enable apache2 vsftpd mysql
    systemctl start apache2 vsftpd mysql

    echo "▶ Настройка vsftpd..."
    
    # Бэкап оригинального файла
    cp /etc/vsftpd.conf /etc/vsftpd.conf.backup
    
    cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
user_sub_token=\$USER
local_root=/var/www/\$USER
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list
EOF

    # Создание необходимых директорий
    mkdir -p /var/run/vsftpd/empty
    
    # Настройка PAM
    echo "# PAM для vsftpd" > /etc/pam.d/vsftpd
    echo "auth required pam_shells.so" >> /etc/pam.d/vsftpd
    echo "auth required pam_unix.so" >> /etc/pam.d/vsftpd
    echo "account required pam_unix.so" >> /etc/pam.d/vsftpd
    echo "session required pam_unix.so" >> /etc/pam.d/vsftpd
    
    # Создание файла пользователей
    touch /etc/vsftpd.user_list
    chmod 644 /etc/vsftpd.user_list

    systemctl restart vsftpd

    a2enmod rewrite ssl
    systemctl reload apache2

    echo "✅ Установка завершена"
}

add_domain() {
    if [ -z "$DOMAIN" ] || [ -z "$FTPPASS" ]; then
        echo "❌ Ошибка: Укажите домен и пароль"
        echo "Использование: ./host.sh add-domain domain password"
        exit 1
    fi
    
    echo "▶ Добавление домена $DOMAIN"
    
    FTPUSER="${DOMAIN//./_}"  # Заменяем точки на подчеркивания для имени пользователя
    SITE_ROOT="$WEB_ROOT/$DOMAIN"
    APACHE_CONF="$APACHE_SITES/$DOMAIN.conf"

    # Создаем пользователя (домен = имя пользователя)
    if ! id "$FTPUSER" &>/dev/null; then
        useradd -m -d "$SITE_ROOT" -s /bin/bash -G www-data "$FTPUSER"
        echo "$FTPUSER:$FTPPASS" | chpasswd
        
        # Создаем директории
        mkdir -p "$SITE_ROOT"/{www,logs,backup}
        mkdir -p "$SITE_ROOT"/www/public_html
        
        # Настройка прав
        chown -R "$FTPUSER:www-data" "$SITE_ROOT"
        chmod -R 755 "$SITE_ROOT"
        chmod 750 "$SITE_ROOT"
        
        # Добавляем в список FTP пользователей
        echo "$FTPUSER" >> /etc/vsftpd.user_list
        
        # Настройка оболочки для FTP доступа
        usermod -s /usr/sbin/nologin "$FTPUSER"
    else
        echo "⚠️  Пользователь $FTPUSER уже существует"
    fi

    # Создаем виртуальный хост Apache
    cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $SITE_ROOT/www/public_html
    
    <Directory $SITE_ROOT/www/public_html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        Order allow,deny
        allow from all
    </Directory>
    
    ErrorLog $SITE_ROOT/logs/error.log
    CustomLog $SITE_ROOT/logs/access.log combined
</VirtualHost>
EOF

    # Создаем тестовую страницу
    cat > "$SITE_ROOT/www/public_html/index.php" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>$DOMAIN</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .success { color: green; font-size: 24px; }
        .info { color: #666; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="success">✅ Сайт $DOMAIN работает!</div>
    <div class="info">Домен: $DOMAIN</div>
    <div class="info">Пользователь FTP: $FTPUSER</div>
    <div class="info">Каталог: $SITE_ROOT/www/public_html</div>
    <div class="info">PHP Version: <?php echo phpversion(); ?></div>
</body>
</html>
EOF

    chown "$FTPUSER:www-data" "$SITE_ROOT/www/public_html/index.php"
    
    # Включаем сайт и перезагружаем Apache
    a2ensite "$DOMAIN.conf"
    systemctl reload apache2
    
    # Настройка MySQL (опционально)
    DBNAME="${FTPUSER}_db"
    DBPASS=$(openssl rand -base64 12)
    mysql -e "CREATE DATABASE IF NOT EXISTS $DBNAME;"
    mysql -e "CREATE USER IF NOT EXISTS '$FTPUSER'@'localhost' IDENTIFIED BY '$DBPASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DBNAME.* TO '$FTPUSER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Создаем файл с данными
    cat > "$SITE_ROOT/.siteinfo" <<EOF
Домен: $DOMAIN
Пользователь FTP: $FTPUSER
Пароль FTP: $FTPPASS
Каталог сайта: $SITE_ROOT/www/public_html
База данных: $DBNAME
Пользователь БД: $FTPUSER
Пароль БД: $DBPASS
EOF
    
    chmod 600 "$SITE_ROOT/.siteinfo"
    chown "$FTPUSER:$FTPUSER" "$SITE_ROOT/.siteinfo"
    
    echo "✅ Домен $DOMAIN добавлен"
    echo ""
    echo "📋 Информация о сайте:"
    echo "   Домен: $DOMAIN"
    echo "   Пользователь FTP: $FTPUSER"
    echo "   Пароль FTP: $FTPPASS"
    echo "   Каталог: $SITE_ROOT/www/public_html"
    echo "   База данных: $DBNAME"
    echo "   Пользователь БД: $FTPUSER"
    echo "   Пароль БД: $DBPASS"
    echo ""
    echo "🔗 Доступ по FTP: ftp://$DOMAIN"
    echo "🔗 Веб-сайт: http://$DOMAIN"
}

del_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Ошибка: Укажите домен"
        echo "Использование: ./host.sh del-domain domain"
        exit 1
    fi
    
    echo "▶ Удаление домена $DOMAIN"
    
    FTPUSER="${DOMAIN//./_}"
    
    # Отключаем сайт в Apache
    a2dissite "$DOMAIN.conf" 2>/dev/null || true
    rm -f "$APACHE_SITES/$DOMAIN.conf"
    
    # Удаляем пользователя из vsftpd.user_list
    sed -i "/^$FTPUSER$/d" /etc/vsftpd.user_list 2>/dev/null || true
    
    # Удаляем пользователя и домашнюю директорию
    userdel -r "$FTPUSER" 2>/dev/null || true
    
    # Удаляем директорию
    rm -rf "$WEB_ROOT/$DOMAIN" 2>/dev/null || true
    
    # Удаляем базу данных MySQL
    mysql -e "DROP DATABASE IF EXISTS ${FTPUSER}_db;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS '$FTPUSER'@'localhost';" 2>/dev/null || true
    
    systemctl reload apache2
    
    echo "✅ Домен $DOMAIN удалён"
}

ssl_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Ошибка: Укажите домен"
        echo "Использование: ./host.sh ssl domain"
        exit 1
    fi
    
    echo "▶ Выпуск SSL для $DOMAIN"
    
    # Проверяем, существует ли конфиг
    if [ ! -f "$APACHE_SITES/$DOMAIN.conf" ]; then
        echo "❌ Ошибка: Домен $DOMAIN не найден"
        exit 1
    fi
    
    # Используем временную почту, если не указана
    EMAIL="admin@$DOMAIN"
    
    certbot --apache -d "$DOMAIN" -d "www.$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
    
    echo "✅ SSL установлен для $DOMAIN"
    echo "🔗 Сайт доступен по HTTPS: https://$DOMAIN"
}

renew_ssl() {
    echo "▶ Обновление SSL сертификатов..."
    certbot renew --quiet
    echo "✅ SSL сертификаты обновлены"
}

list_domains() {
    echo "📋 Список доменов:"
    echo ""
    
    for conf in $APACHE_SITES/*.conf; do
        if [ -f "$conf" ]; then
            DOMAIN=$(basename "$conf" .conf)
            FTPUSER="${DOMAIN//./_}"
            
            if id "$FTPUSER" &>/dev/null; then
                echo "  🌐 $DOMAIN"
                echo "     Пользователь: $FTPUSER"
                echo "     Каталог: $WEB_ROOT/$DOMAIN/www/public_html"
                echo ""
            fi
        fi
    done
}

# GUI функция
show_gui() {
    while true; do
        clear
        echo "========================================="
        echo "          🚀 Панель управления          "
        echo "========================================="
        echo ""
        echo "1. 📦 Установить стек (LAMP + FTP)"
        echo "2. ➕ Добавить домен"
        echo "3. 🗑️  Удалить домен"
        echo "4. 🔐 Установить SSL"
        echo "5. 🔄 Обновить SSL"
        echo "6. 📋 Список доменов"
        echo "7. 📊 Статус сервисов"
        echo "8. 🚪 Выход"
        echo ""
        echo "========================================="
        
        read -p "Выберите действие [1-8]: " choice
        
        case $choice in
            1)
                install_stack
                read -p "Нажмите Enter для продолжения..."
                ;;
            2)
                read -p "Введите домен: " DOMAIN
                read -sp "Введите пароль FTP: " FTPPASS
                echo
                add_domain
                read -p "Нажмите Enter для продолжения..."
                ;;
            3)
                read -p "Введите домен для удаления: " DOMAIN
                del_domain
                read -p "Нажмите Enter для продолжения..."
                ;;
            4)
                read -p "Введите домен для SSL: " DOMAIN
                ssl_domain
                read -p "Нажмите Enter для продолжения..."
                ;;
            5)
                renew_ssl
                read -p "Нажмите Enter для продолжения..."
                ;;
            6)
                list_domains
                read -p "Нажмите Enter для продолжения..."
                ;;
            7)
                echo "📊 Статус сервисов:"
                echo "------------------"
                systemctl status apache2 --no-pager -l
                echo ""
                systemctl status vsftpd --no-pager -l
                echo ""
                systemctl status mysql --no-pager -l
                read -p "Нажмите Enter для продолжения..."
                ;;
            8)
                echo "До свидания!"
                exit 0
                ;;
            *)
                echo "❌ Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

case "$1" in
    install)
        install_stack
        ;;
    add-domain)
        DOMAIN=$2
        FTPPASS=$3
        add_domain
        ;;
    del-domain)
        DOMAIN=$2
        del_domain
        ;;
    ssl)
        DOMAIN=$2
        ssl_domain
        ;;
    renew-ssl)
        renew_ssl
        ;;
    list)
        list_domains
        ;;
    gui)
        show_gui
        ;;
    *)
        echo "🚀 Панель управления хостингом"
        echo "================================"
        echo ""
        echo "Команды:"
        echo "  ./host.sh install                  - Установка стека"
        echo "  ./host.sh add-domain domain pass   - Добавить домен"
        echo "  ./host.sh del-domain domain        - Удалить домен"
        echo "  ./host.sh ssl domain               - Установить SSL"
        echo "  ./host.sh renew-ssl                - Обновить SSL"
        echo "  ./host.sh list                     - Список доменов"
        echo "  ./host.sh gui                      - Графический интерфейс"
        echo ""
        echo "Примеры:"
        echo "  ./host.sh add-domain mysite.ru mypassword"
        echo "  ./host.sh del-domain mysite.ru"
        echo "  ./host.sh ssl mysite.ru"
        ;;
esac
