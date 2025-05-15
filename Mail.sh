#!/bin/bash

set -e

domain="oci.com"
ip_public="103.59.94.63"
reverse_ip="94.59.103"
last_octet="63"
hostname="mail.$domain"

echo "[1/10] Update sistem"
apt update && apt upgrade -y

echo "[2/10] Instalasi paket yang dibutuhkan"
apt install -y bind9 dnsutils postfix dovecot-imapd apache2 php mariadb-server openssl composer \
php-net-smtp php-mysql php-gd php-xml php-mbstring php-intl php-zip php-json php-pear php-bz2 php-gmp \
php-imap php-imagick php-auth-sasl php-mail-mime php-net-ldap3 php-net-sieve php-curl libapache2-mod-php curl

echo "[3/10] Konfigurasi DNS Zone untuk $domain"
cp /etc/bind/db.local /etc/bind/db.$domain
cp /etc/bind/db.127 /etc/bind/db.$reverse_ip

cat > /etc/bind/db.$domain <<EOF
\$TTL 604800
@   IN  SOA ns.$domain. root.$domain. (
        2       ; Serial
        604800  ; Refresh
        86400   ; Retry
        2419200 ; Expire
        604800 ) ; Negative Cache TTL
;
@       IN      NS      ns.$domain.
@       IN      A       $ip_public
ns      IN      A       $ip_public
mail    IN      A       $ip_public
@       IN      MX 10   mail.$domain.
EOF

cat > /etc/bind/db.$reverse_ip <<EOF
\$TTL 604800
@   IN  SOA ns.$domain. root.$domain. (
        1       ; Serial
        604800  ; Refresh
        86400   ; Retry
        2419200 ; Expire
        604800 ) ; Negative Cache TTL
;
@       IN      NS      ns
$last_octet    IN      PTR     mail.$domain.
EOF

echo "zone \"$domain\" {
    type master;
    file \"/etc/bind/db.$domain\";
};

zone \"$reverse_ip.in-addr.arpa\" {
    type master;
    file \"/etc/bind/db.$reverse_ip\";
};" >> /etc/bind/named.conf.local

echo "nameserver 127.0.0.1" > /etc/resolv.conf
systemctl restart bind9

echo "[4/10] Konfigurasi Postfix"
maildirmake.dovecot /etc/skel/Maildir
postconf -e 'home_mailbox = Maildir/'

echo "[5/10] Konfigurasi Dovecot"
sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
sed -i 's|^#disable_plaintext_auth = yes|disable_plaintext_auth = no|' /etc/dovecot/conf.d/10-auth.conf
sed -i 's|^auth_mechanisms =.*|auth_mechanisms = plain login|' /etc/dovecot/conf.d/10-auth.conf

systemctl restart postfix dovecot

echo "[6/10] Membuat user email"
for user in oci leni; do
  useradd -m $user
  echo "$user:password" | chpasswd
done

echo "[7/10] Install Roundcube"
wget https://github.com/roundcube/roundcubemail/releases/download/1.5.2/roundcubemail-1.5.2-complete.tar.gz
mkdir -p /var/www/roundcube
tar -xf roundcubemail-1.5.2-complete.tar.gz -C /var/www/roundcube --strip-components=1

chown -R www-data:www-data /var/www/roundcube/
chmod -R 775 /var/www/roundcube/

echo "[8/10] Konfigurasi Apache untuk Roundcube"
cat > /etc/apache2/sites-available/roundcube.conf <<EOF
<VirtualHost *:80>
    ServerName $hostname
    DocumentRoot /var/www/roundcube/

    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined

    <Directory />
        Options FollowSymLinks
        AllowOverride All
    </Directory>

    <Directory /var/www/roundcube/>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite roundcube.conf
a2enmod rewrite
systemctl restart apache2

echo "[9/10] Instalasi Selesai!"
echo "Akses webmail: http://$hostname"
echo "User: oci | Password: password"
echo "User: leni | Password: password"
