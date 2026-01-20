#!/bin/bash

set -e

ACTION=$1
DOMAIN=$2
FTPPASS=$3

APACHE_SITES="/etc/apache2/sites-available"
WEB_ROOT="/var/www"

# GUI функция
show_gui() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║             🚀 ПАНЕЛЬ УПРАВЛЕНИЯ ХОСТИНГОМ           ║"
        echo "╠══════════════════════════════════════════════════════╣"
        echo "║                                                      ║"
        echo "║  1. 📦 Установить стек (LAMP + FTP + SSL)           ║"
        echo "║  2. ➕ Добавить новый домен                          ║"
        echo "║  3. 🗑️  Удалить домен                               ║"
        echo "║  4. 🔐 Установить SSL сертификат                    ║"
        echo "║  5. 🔄 Обновить все SSL сертификаты                 ║"
        echo "║  6. 🔑 Сменить пароли FTP/MySQL                     ║"
        echo "║  7. 🛠️  Исправить пользователя/домен                ║"
        echo "║  8. 🔧 Переконфигурировать все сервисы              ║"
        echo "║  9. 📋 Список всех доменов                          ║"
        echo "║  10. ℹ️  Информация о домене                         ║"
        echo "║  11. 📊 Статус сервисов                             ║"
        echo "║  12. 🚪 Выход                                       ║"
        echo "║                                                      ║"
        echo "╚══════════════════════════════════════════════════════╝"
        echo ""
        echo "📌 Текущая проблема: пользователь ioc_kz настроен неправильно"
        echo "   Домашняя директория: /var/www/ioc.kz (должна быть доступна)"
        echo ""
        
        read -p "Выберите действие [1-12]: " choice
        
        case $choice in
            1)
                install_stack
                read -p "Нажмите Enter для продолжения..."
                ;;
            2)
                read -p "Введите домен (например: example.com): " DOMAIN
                if [[ -n "$DOMAIN" ]]; then
                    echo ""
                    echo "Пароль FTP будет сгенерирован автоматически."
                    read -p "Или введите свой пароль (оставьте пустым для авто): " FTPPASS
                    add_domain
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            3)
                read -p "Введите домен для удаления: " DOMAIN
                if [[ -n "$DOMAIN" ]]; then
                    del_domain
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            4)
                read -p "Введите домен для SSL: " DOMAIN
                if [[ -n "$DOMAIN" ]]; then
                    ssl_domain
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            5)
                renew_ssl
                read -p "Нажмите Enter для продолжения..."
                ;;
            6)
                read -p "Введите домен: " DOMAIN
                if [[ -n "$DOMAIN" ]]; then
                    echo ""
                    echo "Что сгенерировать заново?"
                    echo "  1. 🔐 Только пароль FTP"
                    echo "  2. 🗄️  Только пароль MySQL"
                    echo "  3. 🔑 Все пароли"
                    read -p "Выберите [1-3]: " pass_choice
                    
                    case $pass_choice in
                        1) TYPE="ftp" ;;
                        2) TYPE="mysql" ;;
                        3) TYPE="all" ;;
                        *) TYPE="all" ;;
                    esac
                    
                    change_password
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            7)
                echo ""
                echo "🛠️  ИСПРАВЛЕНИЕ ПРОБЛЕМ:"
                echo "  1. Исправить пользователя ioc_kz (текущая проблема)"
                echo "  2. Исправить конкретный домен"
                echo "  3. Восстановить все домены"
                read -p "Выберите [1-3]: " fix_choice
                
                case $fix_choice in
                    1)
                        fix_user "ioc_kz"
                        ;;
                    2)
                        read -p "Введите домен: " DOMAIN
                        if [[ -n "$DOMAIN" ]]; then
                            fix_domain
                        fi
                        ;;
                    3)
                        reconfigure_services
                        ;;
                esac
                read -p "Нажмите Enter для продолжения..."
                ;;
            8)
                echo ""
                echo "⚠️  ВНИМАНИЕ: Это переконфигурирует все сервисы!"
                echo "   Будет исправлено:"
                echo "   - Настройки FTP"
                echo "   - Права доступа"
                echo "   - Конфиги Apache"
                echo "   - Директории пользователей"
                read -p "Продолжить? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    reconfigure_services
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            9)
                list_domains
                read -p "Нажмите Enter для продолжения..."
                ;;
            10)
                read -p "Введите домен: " DOMAIN
                if [[ -n "$DOMAIN" ]]; then
                    show_info
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            11)
                show_status
                read -p "Нажмите Enter для продолжения..."
                ;;
            12)
                echo ""
                echo "До свидания! 👋"
                exit 0
                ;;
            *)
                echo "❌ Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

# Функции
install_stack() {
    echo "▶ Установка стека LAMP + FTP + SSL..."
    apt update
    apt install -y apache2 mysql-server php libapache2-mod-php \
        php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip \
        vsftpd certbot python3-certbot-apache ufw
    
    ufw allow 22,80,443,21,20,40000:50000/tcp
    ufw --force enable

    systemctl enable apache2 vsftpd mysql
    systemctl start apache2 vsftpd mysql
    
    reconfigure_services
}

reconfigure_services() {
    echo "🔄 Переконфигурация всех сервисов..."
    
    # Останавливаем FTP
    systemctl stop vsftpd 2>/dev/null || true
    
    # Создаем конфиг vsftpd
    PUBLIC_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    
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
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
ssl_enable=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
pasv_address=$PUBLIC_IP
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list
EOF

    # Создаем необходимые директории
    mkdir -p /var/run/vsftpd/empty
    chmod 755 /var/run/vsftpd/empty
    
    # Исправляем PAM
    cat > /etc/pam.d/vsftpd <<'EOF'
auth    required pam_shells.so
auth    required pam_unix.so
account required pam_unix.so
session required pam_unix.so
EOF

    # Восстанавливаем всех пользователей из user_list
    echo "▶ Восстановление пользователей FTP..."
    
    if [ -f /etc/vsftpd.user_list ]; then
        while read FTPUSER; do
            # Пропускаем пустые строки
            [[ -z "$FTPUSER" ]] && continue
            
            echo "Обработка: $FTPUSER"
            
            if id "$FTPUSER" &>/dev/null; then
                # Получаем текущую домашнюю директорию
                USER_HOME=$(getent passwd "$FTPUSER" | cut -d: -f6)
                
                # Если домашняя директория не существует
                if [ ! -d "$USER_HOME" ]; then
                    echo "  Создание директории: $USER_HOME"
                    mkdir -p "$USER_HOME"
                    mkdir -p "$USER_HOME/www/public_html"
                    
                    # Создаем тестовую страницу
                    cat > "$USER_HOME/www/public_html/index.html" <<HTML
<!DOCTYPE html>
<html>
<head>
    <title>$FTPUSER</title>
</head>
<body>
    <h1>Сайт $FTPUSER</h1>
    <p>Директория восстановлена: $USER_HOME</p>
</body>
</html>
HTML
                fi
                
                # Настраиваем права
                chown -R "$FTPUSER:$FTPUSER" "$USER_HOME"
                chmod -R 755 "$USER_HOME"
                chmod 750 "$USER_HOME"
                
                if [ -d "$USER_HOME/www/public_html" ]; then
                    chown -R "$FTPUSER:www-data" "$USER_HOME/www/public_html"
                    chmod -R 775 "$USER_HOME/www/public_html"
                fi
                
                # Меняем оболочку на /bin/bash
                usermod -s /bin/bash "$FTPUSER"
                
                echo "  ✅ Исправлен"
            else
                echo "  ⚠️  Пользователь не существует"
            fi
        done < /etc/vsftpd.user_list
    fi
    
    # Запускаем сервисы
    systemctl restart vsftpd
    systemctl restart apache2
    systemctl restart mysql
    
    echo ""
    echo "✅ ПЕРЕКОНФИГУРАЦИЯ ЗАВЕРШЕНА"
    echo "============================="
    echo "Список пользователей FTP:"
    cat /etc/vsftpd.user_list 2>/dev/null || echo "Файл не найден"
}

fix_user() {
    FTPUSER=$1
    echo "🛠️  Исправление пользователя: $FTPUSER"
    
    if ! id "$FTPUSER" &>/dev/null; then
        echo "❌ Пользователь не существует"
        return 1
    fi
    
    # Получаем домашнюю директорию
    USER_HOME=$(getent passwd "$FTPUSER" | cut -d: -f6)
    echo "Текущая домашняя директория: $USER_HOME"
    
    # Проверяем существование директории
    if [ ! -d "$USER_HOME" ]; then
        echo "Создание директории: $USER_HOME"
        mkdir -p "$USER_HOME"
        mkdir -p "$USER_HOME/www/public_html"
        
        # Тестовый файл
        cat > "$USER_HOME/www/public_html/index.html" <<HTML
<!DOCTYPE html>
<html>
<head>
    <title>$FTPUSER - Восстановлен</title>
</head>
<body>
    <h1>Сайт $FTPUSER</h1>
    <p>Директория восстановлена: $USER_HOME</p>
    <p>Пользователь: $FTPUSER</p>
    <p>Время: $(date)</p>
</body>
</html>
HTML
    fi
    
    # Настраиваем права
    chown -R "$FTPUSER:$FTPUSER" "$USER_HOME"
    chmod -R 755 "$USER_HOME"
    chmod 750 "$USER_HOME"
    
    if [ -d "$USER_HOME/www/public_html" ]; then
        chown -R "$FTPUSER:www-data" "$USER_HOME/www/public_html"
        chmod -R 775 "$USER_HOME/www/public_html"
    fi
    
    # Меняем оболочку
    usermod -s /bin/bash "$FTPUSER"
    
    # Добавляем в списки FTP если нет
    if [ -f /etc/vsftpd.user_list ] && ! grep -q "^$FTPUSER$" /etc/vsftpd.user_list; then
        echo "$FTPUSER" >> /etc/vsftpd.user_list
    fi
    
    # Перезапускаем FTP
    systemctl restart vsftpd
    
    echo ""
    echo "✅ ПОЛЬЗОВАТЕЛЬ ИСПРАВЛЕН"
    echo "========================"
    echo "Имя: $FTPUSER"
    echo "Домашняя директория: $USER_HOME"
    echo "Оболочка: $(getent passwd "$FTPUSER" | cut -d: -f7)"
    echo ""
    echo "📤 ПРОВЕРКА FTP:"
    echo "  ftp://$FTPUSER:ВАШ_ПАРОЛЬ@$(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
}

fix_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Укажите домен"
        return 1
    fi
    
    FTPUSER="${DOMAIN//./_}"
    SITE_ROOT="$WEB_ROOT/$DOMAIN"
    
    echo "🛠️  Исправление домена: $DOMAIN"
    echo "Пользователь: $FTPUSER"
    
    # Проверяем пользователя
    if ! id "$FTPUSER" &>/dev/null; then
        echo "❌ Пользователь не существует"
        return 1
    fi
    
    # Меняем домашнюю директорию
    CURRENT_HOME=$(getent passwd "$FTPUSER" | cut -d: -f6)
    if [ "$CURRENT_HOME" != "$SITE_ROOT" ]; then
        echo "Изменение домашней директории: $CURRENT_HOME -> $SITE_ROOT"
        usermod -d "$SITE_ROOT" "$FTPUSER"
    fi
    
    # Создаем директорию если нет
    if [ ! -d "$SITE_ROOT" ]; then
        echo "Создание директории: $SITE_ROOT"
        mkdir -p "$SITE_ROOT"
        mkdir -p "$SITE_ROOT/www/public_html"
        mkdir -p "$SITE_ROOT/logs"
        mkdir -p "$SITE_ROOT/backup"
    fi
    
    # Настраиваем права
    chown -R "$FTPUSER:$FTPUSER" "$SITE_ROOT"
    chmod -R 755 "$SITE_ROOT"
    chmod 750 "$SITE_ROOT"
    
    if [ -d "$SITE_ROOT/www/public_html" ]; then
        chown -R "$FTPUSER:www-data" "$SITE_ROOT/www/public_html"
        chmod -R 775 "$SITE_ROOT/www/public_html"
        
        # Тестовый файл
        cat > "$SITE_ROOT/www/public_html/index.html" <<HTML
<!DOCTYPE html>
<html>
<head>
    <title>$DOMAIN - Исправлен</title>
</head>
<body>
    <h1>Сайт $DOMAIN</h1>
    <p>Домен исправлен: $(date)</p>
    <p>Пользователь FTP: $FTPUSER</p>
    <p>Директория: $SITE_ROOT/www/public_html</p>
</body>
</html>
HTML
    fi
    
    # Меняем оболочку
    usermod -s /bin/bash "$FTPUSER"
    
    # Создаем конфиг Apache если нет
    APACHE_CONF="$APACHE_SITES/$DOMAIN.conf"
    if [ ! -f "$APACHE_CONF" ]; then
        echo "Создание конфига Apache..."
        cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $SITE_ROOT/www/public_html
    
    <Directory $SITE_ROOT/www/public_html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog $SITE_ROOT/logs/error.log
    CustomLog $SITE_ROOT/logs/access.log combined
</VirtualHost>
EOF
        a2ensite "$DOMAIN.conf" >/dev/null 2>&1
    fi
    
    # Добавляем в списки FTP
    if [ -f /etc/vsftpd.user_list ] && ! grep -q "^$FTPUSER$" /etc/vsftpd.user_list; then
        echo "$FTPUSER" >> /etc/vsftpd.user_list
    fi
    
    # Перезапускаем сервисы
    systemctl reload apache2
    systemctl restart vsftpd
    
    echo ""
    echo "✅ ДОМЕН ИСПРАВЛЕН"
    echo "================"
    echo "🌐 Сайт: http://$DOMAIN"
    echo "👤 FTP пользователь: $FTPUSER"
    echo "📁 Директория: $SITE_ROOT/www/public_html"
}

add_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Укажите домен"
        return 1
    fi
    
    FTPUSER="${DOMAIN//./_}"
    SITE_ROOT="$WEB_ROOT/$DOMAIN"
    
    echo "➕ Добавление домена: $DOMAIN"
    
    # Генерируем пароль
    if [ -z "$FTPPASS" ]; then
        FTPPASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
    fi
    
    # Создаем пользователя
    if ! id "$FTPUSER" &>/dev/null; then
        useradd -m -d "$SITE_ROOT" -s /bin/bash -G www-data "$FTPUSER"
        echo "$FTPUSER:$FTPPASS" | chpasswd
        echo "✅ Пользователь создан"
    else
        echo "⚠️  Пользователь уже существует"
        echo "$FTPUSER:$FTPPASS" | chpasswd
        echo "✅ Пароль обновлен"
    fi
    
    # Создаем директории
    mkdir -p "$SITE_ROOT/www/public_html"
    mkdir -p "$SITE_ROOT/logs"
    mkdir -p "$SITE_ROOT/backup"
    
    # Настраиваем права
    chown -R "$FTPUSER:$FTPUSER" "$SITE_ROOT"
    chmod -R 755 "$SITE_ROOT"
    chmod 750 "$SITE_ROOT"
    
    chown -R "$FTPUSER:www-data" "$SITE_ROOT/www/public_html"
    chmod -R 775 "$SITE_ROOT/www/public_html"
    
    # Тестовый файл
    cat > "$SITE_ROOT/www/public_html/index.php" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>$DOMAIN</title>
</head>
<body>
    <h1>✅ $DOMAIN работает!</h1>
    <p>Домен: $DOMAIN</p>
    <p>Пользователь FTP: $FTPUSER</p>
    <p>PHP: <?php echo phpversion(); ?></p>
</body>
</html>
EOF
    
    # Конфиг Apache
    APACHE_CONF="$APACHE_SITES/$DOMAIN.conf"
    cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $SITE_ROOT/www/public_html
    
    <Directory $SITE_ROOT/www/public_html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog $SITE_ROOT/logs/error.log
    CustomLog $SITE_ROOT/logs/access.log combined
</VirtualHost>
EOF
    
    a2ensite "$DOMAIN.conf"
    
    # Добавляем в FTP
    echo "$FTPUSER" >> /etc/vsftpd.user_list
    
    # MySQL
    DBNAME="${FTPUSER}_db"
    DBPASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
    
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$DBNAME\`;" 2>/dev/null || true
    mysql -e "CREATE USER IF NOT EXISTS '$FTPUSER'@'localhost' IDENTIFIED BY '$DBPASS';" 2>/dev/null || true
    mysql -e "GRANT ALL ON \`$DBNAME\`.* TO '$FTPUSER'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    # Файл с информацией
    cat > "$SITE_ROOT/.siteinfo" <<EOF
Домен: $DOMAIN
FTP пользователь: $FTPUSER
FTP пароль: $FTPPASS
База данных: $DBNAME
MySQL пользователь: $FTPUSER
MySQL пароль: $DBPASS
Директория: $SITE_ROOT/www/public_html
EOF
    
    chmod 600 "$SITE_ROOT/.siteinfo"
    chown "$FTPUSER:$FTPUSER" "$SITE_ROOT/.siteinfo"
    
    # Перезапускаем
    systemctl reload apache2
    systemctl restart vsftpd
    
    echo ""
    echo "✅ ДОМЕН ДОБАВЛЕН"
    echo "==============="
    echo "🌐 Сайт: http://$DOMAIN"
    echo "📤 FTP: $FTPUSER : $FTPPASS"
    echo "🗄️  MySQL: $DBNAME : $DBPASS"
    echo "📁 Папка: $SITE_ROOT/www/public_html"
}

del_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Укажите домен"
        return 1
    fi
    
    FTPUSER="${DOMAIN//./_}"
    
    echo "🗑️  Удаление домена: $DOMAIN"
    read -p "Вы уверены? (y/N): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo "❌ Отменено"
        return
    fi
    
    # Удаляем из Apache
    a2dissite "$DOMAIN.conf" 2>/dev/null || true
    rm -f "$APACHE_SITES/$DOMAIN.conf"
    rm -f "$APACHE_SITES/$DOMAIN-le-ssl.conf" 2>/dev/null || true
    
    # Удаляем из FTP
    sed -i "/^$FTPUSER$/d" /etc/vsftpd.user_list 2>/dev/null || true
    
    # Удаляем пользователя
    userdel -r "$FTPUSER" 2>/dev/null || true
    
    # Удаляем директорию
    rm -rf "$WEB_ROOT/$DOMAIN" 2>/dev/null || true
    
    # Удаляем базу данных
    mysql -e "DROP DATABASE IF EXISTS \`${FTPUSER}_db\`;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS '$FTPUSER'@'localhost';" 2>/dev/null || true
    
    systemctl reload apache2
    systemctl restart vsftpd
    
    echo "✅ Домен удален"
}

ssl_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Укажите домен"
        return 1
    fi
    
    echo "🔐 Установка SSL для: $DOMAIN"
    
    certbot --apache -d "$DOMAIN" -d "www.$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "admin@$DOMAIN" \
        --redirect
    
    echo "✅ SSL установлен: https://$DOMAIN"
}

renew_ssl() {
    echo "🔄 Обновление SSL сертификатов..."
    certbot renew --quiet
    echo "✅ SSL обновлены"
}

change_password() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Укажите домен"
        return 1
    fi
    
    FTPUSER="${DOMAIN//./_}"
    TYPE=${3:-"all"}
    
    echo "🔑 Смена паролей для: $DOMAIN"
    
    if [ "$TYPE" = "ftp" ] || [ "$TYPE" = "all" ]; then
        NEW_FTP_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
        echo "$FTPUSER:$NEW_FTP_PASS" | chpasswd
        echo "✅ FTP пароль: $NEW_FTP_PASS"
    fi
    
    if [ "$TYPE" = "mysql" ] || [ "$TYPE" = "all" ]; then
        NEW_DB_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)
        mysql -e "ALTER USER '$FTPUSER'@'localhost' IDENTIFIED BY '$NEW_DB_PASS';" 2>/dev/null || true
        echo "✅ MySQL пароль: $NEW_DB_PASS"
    fi
}

list_domains() {
    echo "📋 СПИСОК ДОМЕНОВ"
    echo "================"
    echo ""
    
    count=0
    for conf in $APACHE_SITES/*.conf; do
        if [ -f "$conf" ] && [[ ! "$conf" =~ "default" ]] && [[ ! "$conf" =~ "000" ]]; then
            DOMAIN=$(basename "$conf" .conf)
            FTPUSER="${DOMAIN//./_}"
            
            echo "🌐 $DOMAIN"
            echo "   👤 Пользователь: $FTPUSER"
            echo "   📁 Директория: $WEB_ROOT/$DOMAIN"
            
            # Проверяем SSL
            if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
                echo "   🔐 SSL: Установлен"
            else
                echo "   🔐 SSL: Не установлен"
            fi
            
            echo ""
            ((count++))
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo "ℹ️  Домены не найдены"
    else
        echo "📊 Всего: $count домен(ов)"
    fi
}

show_info() {
    if [ -z "$DOMAIN" ]; then
        echo "❌ Укажите домен"
        return 1
    fi
    
    FTPUSER="${DOMAIN//./_}"
    SITE_ROOT="$WEB_ROOT/$DOMAIN"
    
    echo "ℹ️  ИНФОРМАЦИЯ О ДОМЕНЕ: $DOMAIN"
    echo "================================"
    echo ""
    
    # Проверяем пользователя
    if id "$FTPUSER" &>/dev/null; then
        echo "✅ Пользователь существует: $FTPUSER"
        echo "   Домашняя директория: $(getent passwd "$FTPUSER" | cut -d: -f6)"
        echo "   Оболочка: $(getent passwd "$FTPUSER" | cut -d: -f7)"
    else
        echo "❌ Пользователь не существует"
    fi
    
    echo ""
    
    # Проверяем директорию
    if [ -d "$SITE_ROOT" ]; then
        echo "✅ Директория существует: $SITE_ROOT"
        echo "   Размер: $(du -sh "$SITE_ROOT" 2>/dev/null | cut -f1)"
    else
        echo "❌ Директория не существует"
    fi
    
    echo ""
    
    # Проверяем Apache
    if [ -f "$APACHE_SITES/$DOMAIN.conf" ]; then
        echo "✅ Конфиг Apache существует"
    else
        echo "❌ Конфиг Apache не найден"
    fi
    
    echo ""
    
    # Проверяем FTP
    if grep -q "^$FTPUSER$" /etc/vsftpd.user_list 2>/dev/null; then
        echo "✅ В списке FTP пользователей"
    else
        echo "❌ Нет в списке FTP пользователей"
    fi
    
    echo ""
    
    # Проверяем SSL
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        echo "✅ SSL сертификат установлен"
    else
        echo "❌ SSL сертификат не установлен"
    fi
}

show_status() {
    echo "📊 СТАТУС СЕРВИСОВ"
    echo "=================="
    echo ""
    
    echo "🌐 Apache2:"
    if systemctl is-active apache2 >/dev/null; then
        echo "  ✅ Работает"
    else
        echo "  ❌ Не работает"
    fi
    
    echo ""
    echo "📤 FTP (vsftpd):"
    if systemctl is-active vsftpd >/dev/null; then
        echo "  ✅ Работает"
        echo "  👥 Пользователей: $(wc -l /etc/vsftpd.user_list 2>/dev/null | cut -d' ' -f1 || echo 0)"
    else
        echo "  ❌ Не работает"
    fi
    
    echo ""
    echo "🗄️  MySQL:"
    if systemctl is-active mysql >/dev/null; then
        echo "  ✅ Работает"
    else
        echo "  ❌ Не работает"
    fi
    
    echo ""
    echo "🛡️  Брандмауэр (UFW):"
    ufw status | grep -E "Status|действует" | head -1
    
    echo ""
    echo "💾 Дисковое пространство:"
    df -h /var/www | tail -1
}

# Запуск
case "$1" in
    install)
        install_stack
        ;;
    add-domain)
        DOMAIN=$2
        FTPPASS=$3
        add_domain
        ;;
    fix-user)
        fix_user "$2"
        ;;
    fix-domain)
        DOMAIN=$2
        fix_domain
        ;;
    gui)
        show_gui
        ;;
    *)
        echo "Для запуска GUI используйте: ./host.sh gui"
        echo ""
        echo "Или исправьте текущую проблему:"
        echo "  ./host.sh fix-user ioc_kz"
        echo "  ./host.sh reconfigure"
        ;;
esac
