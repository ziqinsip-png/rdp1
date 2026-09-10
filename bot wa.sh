#!/bin/bash
# =================================================================
# UNATTENDED PTERODACTYL SETUP v2.0 (PHP 8.2 & AZURE INTEGRATED)
# =================================================================

export DEBIAN_FRONTEND=noninteractive

# Konfigurasi Utama
PANEL_DOMAIN="panel.paridx.my.id"
WINGS_DOMAIN="wings.paridx.my.id"
PANEL_PORT=80
DB_PASS="${SETUP_DB_PASS}"

echo -e "\e[36m[+] Memulai instalasi Pterodactyl Suite...\e[0m"

# 1. Install Dependensi Khusus Panel (Tanpa Docker/Update Global)
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg tar unzip redis-server mariadb-server nginx

# 2. Tambah Repo & Install PHP 8.2
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y php8.2 php8.2-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}

# Set default PHP ke 8.2 untuk berjaga-jaga
update-alternatives --set php /usr/bin/php8.2

# 3. Setup Database MariaDB (Otomatis)
systemctl start mariadb
mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mysql -u root -e "CREATE DATABASE panel;"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

# 4. Unduh & Ekstrak File Panel Pterodactyl
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# 5. Install Composer & Dependensi Panel
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
cp .env.example .env
composer install --no-dev --optimize-autoloader

# 6. Konfigurasi Panel Pterodactyl & Pembuatan Akun
php artisan key:generate --force
php artisan p:environment:setup \
    --author="saintparid@gmail.com" \
    --url="https://${PANEL_DOMAIN}" \
    --timezone="Asia/Jakarta" \
    --cache="redis" \
    --session="database" \
    --queue="redis" \
    --telemetry=false

php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pterodactyl" \
    --password="${DB_PASS}"

php artisan migrate --seed --force

# SYARAT MUTLAK: Pembuatan Akun Admin Khusus Paduka
php artisan p:user:make \
    --email="saintparid@gmail.com" \
    --username="parid" \
    --name-first="Farid" \
    --name-last="A." \
    --password="paridos" \
    --admin=1

chown -R www-data:www-data /var/www/pterodactyl/*

# 7. Setup Nginx (Integrasi dengan Port 80 & Socket PHP 8.2)
cat <<EOF > /etc/nginx/sites-available/pterodactyl.conf
server {
    listen $PANEL_PORT;
    server_name $PANEL_DOMAIN;
    root /var/www/pterodactyl/public;
    index index.php;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# 8. Konfigurasi Cron & Worker Pterodactyl
echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" | crontab -
cat <<EOF > /etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now pteroq.service

# 9. Unduh & Siapkan Wings (Karena Docker sudah ada)
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
chmod u+x /usr/local/bin/wings

cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
systemctl enable wings
docker network create pterodactyl_nw

echo -e "\e[32m[V] PTERODACTYL SUITE SELESAI DIEKSEKUSI!\e[0m"
echo -e "\e[33mSilakan login ke https://${PANEL_DOMAIN}\e[0m"
echo -e "\e[33mEmail: saintparid@gmail.com | Username: parid | Pass: paridos\e[0m"
