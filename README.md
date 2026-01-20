# Mini Hosting Manager (Apache + FTP + SSL)

Bash-скрипт для автоматического развёртывания мини-хостинга на Ubuntu.
Позволяет одной командой устанавливать стек, добавлять и удалять домены,
создавать FTP-пользователей и управлять SSL-сертификатами Let's Encrypt.

## 🚀 Возможности

- Установка Apache, PHP, MySQL, vsftpd, Certbot
- Автоматическое создание домена (VirtualHost)
- Привязка домена к каталогу `/home/DOMAIN/www`
- Создание FTP-пользователя под домен
- Ограничение FTP-пользователя своим каталогом (chroot)
- Установка и продление SSL (Let's Encrypt)
- Удаление доменов
- Повторный запуск без конфликтов
- Работает как mini-cPanel

## 📦 Требования

- Ubuntu 20.04 / 22.04
- Root-доступ (`sudo`)
- Открытые порты:
  - 80 / 443 (HTTP / HTTPS)
  - 21 (FTP)

## 🛠 Установка

```bash
git clone https://github.com/alim989898/mini-hosting-manager.git
cd mini-hosting-manager
chmod +x host.sh

# Установить стек (Apache, PHP, MySQL, FTP, SSL)
sudo ./host.sh install

# Добавить домен + FTP пользователя
sudo ./host.sh add-domain example.com ftpuser StrongPassword123

# Установить SSL (Let's Encrypt)
sudo ./host.sh ssl example.com

# Обновить SSL для всех доменов
sudo ./host.sh renew-ssl

# Удалить домен
sudo ./host.sh del-domain example.com


sudo systemctl status apache2
sudo systemctl status vsftpd

