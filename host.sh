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

generate_password() {
    openssl rand -base64 12 | tr -d '/+' | cut -c1-12
}

add_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Ошибка: Укажите домен"
        echo "Использование: ./host.sh add-domain domain [password]"
        exit 1
    fi
    
    echo "▶ Добавление домена $DOMAIN"
    
    FTPUSER="${DOMAIN//./_}"  # Заменяем точки на подчеркивания для имени пользователя
    SITE_ROOT="$WEB_ROOT/$DOMAIN"
    APACHE_CONF="$APACHE_SITES/$DOMAIN.conf"

    # Генерируем пароль FTP, если не указан
    if [ -z "$FTPPASS" ]; then
        FTPPASS=$(generate_password)
        echo "🔐 Автоматически сгенерирован пароль FTP: $FTPPASS"
    fi

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
    
    # Настройка MySQL
    DBNAME="${FTPUSER}_db"
    DBPASS=$(generate_password)
    mysql -e "CREATE DATABASE IF NOT EXISTS $DBNAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
    mysql -e "CREATE USER IF NOT EXISTS '$FTPUSER'@'localhost' IDENTIFIED BY '$DBPASS';" 2>/dev/null || true
    mysql -e "GRANT ALL PRIVILEGES ON $DBNAME.* TO '$FTPUSER'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
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
    echo "📝 Все данные сохранены в: $SITE_ROOT/.siteinfo"
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

change_password() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Ошибка: Укажите домен"
        echo "Использование: ./host.sh change-password domain [type]"
        echo "  type: ftp, mysql, all (по умолчанию: all)"
        exit 1
    fi
    
    TYPE=${2:-all}
    FTPUSER="${DOMAIN//./_}"
    SITE_ROOT="$WEB_ROOT/$DOMAIN"
    
    if [ ! -d "$SITE_ROOT" ]; then
        echo "❌ Ошибка: Домен $DOMAIN не найден"
        exit 1
    fi
    
    echo "▶ Смена паролей для $DOMAIN"
    
    case $TYPE in
        ftp|all)
            # Генерируем новый пароль FTP
            NEW_FTP_PASS=$(generate_password)
            echo "$FTPUSER:$NEW_FTP_PASS" | chpasswd
            
            # Обновляем файл .siteinfo
            if [ -f "$SITE_ROOT/.siteinfo" ]; then
                sed -i "s/Пароль FTP:.*/Пароль FTP: $NEW_FTP_PASS/" "$SITE_ROOT/.siteinfo"
            fi
            
            echo "🔐 Новый пароль FTP: $NEW_FTP_PASS"
            ;;
    esac
    
    case $TYPE in
        mysql|all)
            # Генерируем новый пароль MySQL
            NEW_DB_PASS=$(generate_password)
            
            # Меняем пароль пользователя MySQL
            mysql -e "ALTER USER '$FTPUSER'@'localhost' IDENTIFIED BY '$NEW_DB_PASS';" 2>/dev/null || true
            mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
            
            # Обновляем файл .siteinfo
            if [ -f "$SITE_ROOT/.siteinfo" ]; then
                sed -i "s/Пароль БД:.*/Пароль БД: $NEW_DB_PASS/" "$SITE_ROOT/.siteinfo"
            fi
            
            echo "🗄️  Новый пароль MySQL: $NEW_DB_PASS"
            ;;
    esac
    
    # Если .siteinfo существует, показываем все данные
    if [ -f "$SITE_ROOT/.siteinfo" ]; then
        echo ""
        echo "📋 Обновленная информация о сайте:"
        cat "$SITE_ROOT/.siteinfo"
    fi
    
    echo "✅ Пароли успешно изменены"
}

show_info() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Ошибка: Укажите домен"
        echo "Использование: ./host.sh info domain"
        exit 1
    fi
    
    FTPUSER="${DOMAIN//./_}"
    SITE_ROOT="$WEB_ROOT/$DOMAIN"
    
    if [ ! -d "$SITE_ROOT" ]; then
        echo "❌ Ошибка: Домен $DOMAIN не найден"
        exit 1
    fi
    
    echo "📋 Информация о домене $DOMAIN"
    echo "================================"
    
    if [ -f "$SITE_ROOT/.siteinfo" ]; then
        cat "$SITE_ROOT/.siteinfo"
    else
        echo "Информация:"
        echo "  Домен: $DOMAIN"
        echo "  Пользователь FTP: $FTPUSER"
        echo "  Каталог: $SITE_ROOT/www/public_html"
        echo "  База данных: ${FTPUSER}_db"
        echo "  Пользователь БД: $FTPUSER"
        echo ""
        echo "⚠️  Файл .siteinfo не найден. Пароли не отображаются."
        echo "   Используйте ./host.sh change-password $DOMAIN для сброса паролей."
    fi
    
    # Проверяем SSL
    echo ""
    echo "🔐 SSL сертификат:"
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        echo "  ✅ Установлен"
        echo "  Срок действия:"
        openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -dates | grep notAfter | cut -d= -f2
    else
        echo "  ❌ Не установлен"
        echo "  Используйте: ./host.sh ssl $DOMAIN"
    fi
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
                
                # Показываем SSL статус
                if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
                    echo "     SSL: ✅ Установлен"
                else
                    echo "     SSL: ❌ Отсутствует"
                fi
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
        echo "6. 🔑 Сменить пароли"
        echo "7. ℹ️  Информация о домене"
        echo "8. 📋 Список доменов"
        echo "9. 📊 Статус сервисов"
        echo "10. 🚪 Выход"
        echo ""
        echo "========================================="
        
        read -p "Выберите действие [1-10]: " choice
        
        case $choice in
            1)
                install_stack
                read -p "Нажмите Enter для продолжения..."
                ;;
            2)
                read -p "Введите домен: " DOMAIN
                echo "Пароль FTP будет сгенерирован автоматически."
                echo "Если хотите указать свой пароль, введите его ниже,"
                read -p "иначе оставьте пустым: " FTPPASS
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
                read -p "Введите домен: " DOMAIN
                echo "Что сгенерировать заново?"
                echo "1. Пароль FTP"
                echo "2. Пароль MySQL"
                echo "3. Все пароли"
                read -p "Выберите [1-3]: " pass_choice
                
                case $pass_choice in
                    1) TYPE="ftp" ;;
                    2) TYPE="mysql" ;;
                    3) TYPE="all" ;;
                    *) TYPE="all" ;;
                esac
                
                change_password "$DOMAIN" "$TYPE"
                read -p "Нажмите Enter для продолжения..."
                ;;
            7)
                read -p "Введите домен: " DOMAIN
                show_info
                read -p "Нажмите Enter для продолжения..."
                ;;
            8)
                list_domains
                read -p "Нажмите Enter для продолжения..."
                ;;
            9)
                echo "📊 Статус сервисов:"
                echo "------------------"
                systemctl status apache2 --no-pager -l
                echo ""
                systemctl status vsftpd --no-pager -l
                echo ""
                systemctl status mysql --no-pager -l
                read -p "Нажмите Enter для продолжения..."
                ;;
            10)
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
    change-password)
        DOMAIN=$2
        TYPE=$3
        change_password "$DOMAIN" "$TYPE"
        ;;
    info)
        DOMAIN=$2
        show_info
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
        echo "  ./host.sh add-domain domain [pass] - Добавить домен"
        echo "  ./host.sh del-domain domain        - Удалить домен"
        echo "  ./host.sh ssl domain               - Установить SSL"
        echo "  ./host.sh renew-ssl                - Обновить SSL"
        echo "  ./host.sh change-password domain [type] - Сменить пароли"
        echo "      type: ftp, mysql, all (по умолчанию: all)"
        echo "  ./host.sh info domain              - Информация о домене"
        echo "  ./host.sh list                     - Список доменов"
        echo "  ./host.sh gui                      - Графический интерфейс"
        echo ""
        echo "Примеры:"
        echo "  ./host.sh add-domain mysite.ru                 # Пароль сгенерируется"
        echo "  ./host.sh add-domain mysite.ru mypassword123   # Своим паролем"
        echo "  ./host.sh change-password mysite.ru ftp        # Сменить только FTP"
        echo "  ./host.sh change-password mysite.ru mysql      # Сменить только MySQL"
        echo "  ./host.sh change-password mysite.ru            # Сменить все пароли"
        echo "  ./host.sh info mysite.ru                       # Показать данные"
        ;;
esac
