#!/bin/bash

set -e

ACTION=$1
DOMAIN=$2
FTPUSER=$3
FTPPASS=$4

APACHE_SITES="/etc/apache2/sites-available"
WEB_ROOT="/home"

install_stack() {
    echo "▶ Установка Apache, PHP, MySQL, FTP, SSL..."
    apt update
    apt install -y apache2 mysql-server php libapache2-mod-php \
        php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip \
        vsftpd certbot python3-certbot-apache

    systemctl enable apache2 vsftpd
    systemctl start apache2 vsftpd

    echo "▶ Настройка vsftpd..."
    cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/home/\$USER/www
pam_service_name=vsftpd
userlist_enable=YES
userlist_deny=NO
EOF

    touch /etc/vsftpd.userlist
    systemctl restart vsftpd

    a2enmod rewrite ssl
    systemctl reload apache2

    echo "✅ Установка завершена"
}

add_domain() {
    echo "▶ Добавление домена $DOMAIN"

    SITE_ROOT="$WEB_ROOT/$DOMAIN/www"
    APACHE_CONF="$APACHE_SITES/$DOMAIN.conf"

    mkdir -p "$SITE_ROOT"

    if ! id "$FTPUSER" &>/dev/null; then
        useradd -d "$WEB_ROOT/$DOMAIN" -s /usr/sbin/nologin "$FTPUSER"
        echo "$FTPUSER:$FTPPASS" | chpasswd
        echo "$FTPUSER" >> /etc/vsftpd.userlist
    fi

    chown -R "$FTPUSER:www-data" "$WEB_ROOT/$DOMAIN"
    chmod -R 755 "$WEB_ROOT/$DOMAIN"

    cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $SITE_ROOT

    <Directory $SITE_ROOT>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF

    a2ensite "$DOMAIN.conf"
    systemctl reload apache2

    cat > "$SITE_ROOT/index.php" <<EOF
<?php
echo "Site $DOMAIN works!";
EOF

    chown "$FTPUSER:www-data" "$SITE_ROOT/index.php"

    echo "✅ Домен $DOMAIN добавлен"
}

del_domain() {
    echo "▶ Удаление домена $DOMAIN"

    a2dissite "$DOMAIN.conf" || true
    rm -f "$APACHE_SITES/$DOMAIN.conf"
    rm -rf "$WEB_ROOT/$DOMAIN"

    systemctl reload apache2

    echo "✅ Домен $DOMAIN удалён"
}

ssl_domain() {
    echo "▶ Выпуск SSL для $DOMAIN"
    certbot --apache -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN
    echo "✅ SSL установлен"
}

renew_ssl() {
    certbot renew
    echo "✅ SSL обновлены"
}

case "$ACTION" in
    install)
        install_stack
        ;;
    add-domain)
        add_domain
        ;;
    del-domain)
        del_domain
        ;;
    ssl)
        ssl_domain
        ;;
    renew-ssl)
        renew_ssl
        ;;
    *)
        echo "Использование:"
        echo "  ./host.sh install"
        echo "  ./host.sh add-domain domain ftpuser password"
        echo "  ./host.sh del-domain domain"
        echo "  ./host.sh ssl domain"
        echo "  ./host.sh renew-ssl"
        ;;
esac
