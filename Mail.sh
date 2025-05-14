#!/bin/bash

# Konfigurasi
domain="oci.com"
ip_public="103.176.79.123"
reverse_ip="79.176.103"
last_octet="123"
hostname="mail.$domain"

# Update dan install dependency
echo "[+] Update dan install paket awal..."
apt update && apt upgrade -y
apt install -y software-properties-common debconf-utils wget gnupg curl nano

# Set hostname
echo "[+] Set hostname ke $hostname..."
hostnamectl set-hostname $hostname
echo "$ip_public $hostname" >> /etc/hosts

# Preseed konfigurasi Postfix
echo "[+] Konfigurasi otomatis Postfix..."
echo "postfix postfix/mailname string $hostname" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections

# Install Postfix dan Dovecot tanpa interaktif
echo "[+] Install Postfix dan Dovecot..."
DEBIAN_FRONTEND=noninteractive apt install -y postfix dovecot-core dovecot-imapd

# Konfigurasi Postfix
echo "[+] Konfigurasi Postfix..."
postconf -e "myhostname = $hostname"
postconf -e "mydomain = $domain"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "home_mailbox = Maildir/"
postconf -e "smtpd_banner = \$myhostname ESMTP \$mail_name"
postconf -e "smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache"
postconf -e "smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache"

# Buat user mail
echo "[+] Membuat user oci dan leni..."
useradd -m oci
echo "oci:passwordoci" | chpasswd
useradd -m leni
echo "leni:passwordleni" | chpasswd

# Buat folder Maildir untuk masing-masing user
echo "[+] Membuat Maildir..."
for user in oci leni; do
  su - $user -c "mkdir -p ~/Maildir/{cur,new,tmp}"
done

# Konfigurasi Dovecot
echo "[+] Konfigurasi Dovecot..."
cat <<EOF > /etc/dovecot/dovecot.conf
disable_plaintext_auth = no
mail_privileged_group = mail
mail_location = maildir:~/Maildir
userdb {
  driver = passwd
}
passdb {
  driver = pam
}
protocols = imap pop3 lmtp
EOF

# Aktifkan dan restart layanan
echo "[+] Restart layanan..."
systemctl restart postfix
systemctl restart dovecot
systemctl enable postfix
systemctl enable dovecot

# Install Roundcube Webmail (via apt)
echo "[+] Install Roundcube..."
DEBIAN_FRONTEND=noninteractive apt install -y roundcube roundcube-core roundcube-mysql roundcube-plugins roundcube-plugins-extra

# Konfigurasi Reverse DNS (contoh Bind9)
echo "[+] Konfigurasi reverse DNS..."
apt install -y bind9

cat <<EOF > /etc/bind/db.$reverse_ip
\$TTL 604800
@   IN  SOA ns.$domain. root.$domain. (
            2         ; Serial
            604800    ; Refresh
            86400     ; Retry
            2419200   ; Expire
            604800 )  ; Negative Cache TTL

@       IN  NS      ns.$domain.
$last_octet  IN  PTR     mail.$domain.
EOF

echo "zone \"$reverse_ip.in-addr.arpa\" {
    type master;
    file \"/etc/bind/db.$reverse_ip\";
};" >> /etc/bind/named.conf.local

systemctl restart bind9
systemctl enable bind9

echo "[✔] Mail server selesai dikonfigurasi!"
echo "Akses Webmail: http://$ip_public/roundcube"
