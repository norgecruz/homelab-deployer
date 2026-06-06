#!/bin/bash

set -e

ZABBIX_VERSION="7.0"
DB_NAME="zabbix"
DB_USER="zabbix"
DB_PASS="ZabbixPass123!"
TIMEZONE="America/Montevideo"

echo "=== Iniciando despliegue de Zabbix en Debian ==="

if [ "$EUID" -ne 0 ]; then
   echo "Ejecute este script como root o con sudo:"
   echo "sudo bash deploy_zabbix_mariadb.sh"
   exit 1
fi

if [ -f /etc/os-release ]; then
   . /etc/os-release
else
   echo "No se pudo detectar el sistema operativo."
   exit 1
fi

if [ "$ID" = "debian" ]; then
   echo "Debian detectado: $VERSION_ID - $VERSION_CODENAME"
else
   echo "Este script está pensado para Debian."
   exit 1
fi

if [ "$VERSION_ID" = "12" ]; then
   DEBIAN_VERSION="12"
elif [ "$VERSION_ID" = "13" ]; then
   DEBIAN_VERSION="13"
else
   echo "Versión Debian no soportada por este script: $VERSION_ID"
   echo "Use Debian 12 o Debian 13."
   exit 1
fi

echo "Actualizando sistema..."
apt update
apt install -y wget curl gnupg2 ca-certificates lsb-release locales

echo "Configurando locale..."
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "Instalando repositorio oficial de Zabbix..."
cd /tmp
wget -O zabbix-release.deb "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/debian/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_VERSION}+debian${DEBIAN_VERSION}_all.deb"
dpkg -i zabbix-release.deb
apt update

echo "Instalando Zabbix + MariaDB + Apache..."
apt install -y \
   zabbix-server-mysql \
   zabbix-frontend-php \
   zabbix-apache-conf \
   zabbix-sql-scripts \
   zabbix-agent2 \
   mariadb-server \
   apache2

echo "Activando MariaDB..."
systemctl enable --now mariadb

echo "Configurando base de datos MariaDB..."

mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

echo "Importando esquema inicial de Zabbix..."

TABLES=$(mysql -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';")

if [ "$TABLES" = "0" ]; then
   zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -u"$DB_USER" -p"$DB_PASS" "$DB_NAME"
else
   echo "La base de datos ya tiene tablas. No se procede a importar de nuevo."
fi

echo "Desactivando permiso temporal de funciones..."
mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

echo "Configurando Zabbix Server..."
sed -i "s/^# DBPassword=.*/DBPassword=$DB_PASS/" /etc/zabbix/zabbix_server.conf
sed -i "s/^DBPassword=.*/DBPassword=$DB_PASS/" /etc/zabbix/zabbix_server.conf

if ! grep -q "^DBPassword=" /etc/zabbix/zabbix_server.conf; then
   echo "DBPassword=$DB_PASS" >> /etc/zabbix/zabbix_server.conf
fi

echo "Configurando zona horaria PHP..."
sed -i "s|^.*php_value date.timezone.*|        php_value date.timezone $TIMEZONE|" /etc/zabbix/apache.conf

echo "Reiniciando servicios..."
systemctl restart zabbix-server zabbix-agent2 apache2 mariadb
systemctl enable zabbix-server zabbix-agent2 apache2 mariadb

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================="
echo " Zabbix instalado correctamente con MariaDB"
echo "=========================================="
echo "URL: http://$IP/zabbix"
echo ""
echo "Base de datos:"
echo "DB: $DB_NAME"
echo "Usuario DB: $DB_USER"
echo "Password DB: $DB_PASS"
echo ""
echo "Login web inicial:"
echo "Usuario: Admin"
echo "Password: zabbix"
echo ""
echo "IMPORTANTE:"
echo "Cuando entres por primera vez, cambia la contraseña de Admin."
echo "=========================================="
