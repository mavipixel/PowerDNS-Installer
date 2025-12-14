#!/bin/bash

###############################################################################
# PowerDNS ve PowerAdmin Otomatik Kurulum Scripti
# AlmaLinux 9 için
# Kaynak: https://orcacore.com/install-powerdns-almalinux-9/
###############################################################################

set -e  # Hata durumunda scripti durdur

# Renk kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log fonksiyonu
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root kontrolü
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Bu script root yetkisi ile çalıştırılmalıdır!"
        exit 1
    fi
}

# SELinux kontrolü
check_selinux() {
    if [ -f /etc/selinux/config ]; then
        SELINUX_STATUS=$(getenforce)
        if [ "$SELINUX_STATUS" != "Disabled" ] && [ "$SELINUX_STATUS" != "Permissive" ]; then
            log_warn "SELinux etkin durumda. PowerDNS düzgün çalışması için SELinux'un devre dışı bırakılması önerilir."
            log_warn "SELinux'u devre dışı bırakmak için: setenforce 0"
            read -p "Devam etmek istiyor musunuz? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Kullanıcıdan bilgi alma
get_user_input() {
    log_info "PowerDNS kurulumu için gerekli bilgileri girin:"
    echo ""
    
    read -p "MariaDB root şifresi: " MYSQL_ROOT_PASS
    read -p "PowerDNS veritabanı adı (varsayılan: powerdb): " POWERDB_NAME
    POWERDB_NAME=${POWERDB_NAME:-powerdb}
    
    read -p "PowerDNS veritabanı kullanıcı adı (varsayılan: poweruser): " POWERDB_USER
    POWERDB_USER=${POWERDB_USER:-poweruser}
    
    read -sp "PowerDNS veritabanı kullanıcı şifresi: " POWERDB_PASS
    echo ""
    
    read -sp "PowerAdmin yönetici şifresi: " POWERADMIN_PASS
    echo ""
    
    read -p "PowerAdmin kullanıcı adı (varsayılan: admin): " POWERADMIN_USER
    POWERADMIN_USER=${POWERADMIN_USER:-admin}
    
    read -p "Hostmaster e-posta (varsayılan: admin@example.com): " HOSTMASTER
    HOSTMASTER=${HOSTMASTER:-admin@example.com}
    
    read -p "Nameserver (varsayılan: ns1.example.com): " NAMESERVER
    NAMESERVER=${NAMESERVER:-ns1.example.com}
}

###############################################################################
# Adım 1: PowerDNS Bağımlılıklarını Kurma
###############################################################################
install_dependencies() {
    log_info "Adım 1: Sistem güncellemesi ve bağımlılıklar kuruluyor..."
    
    # Sistem güncellemesi
    log_info "Sistem paketleri güncelleniyor..."
    dnf update -y
    
    # EPEL repository
    log_info "EPEL repository kuruluyor..."
    dnf -y install epel-release
    
    # Remi repository
    log_info "Remi repository kuruluyor..."
    dnf -y install http://rpms.remirepo.net/enterprise/remi-release-9.rpm
    
    # PHP Remi 7.4 modülünü etkinleştir
    log_info "PHP Remi 7.4 modülü etkinleştiriliyor..."
    dnf module enable php:remi-7.4 -y
    
    log_info "Adım 1 tamamlandı!"
}

###############################################################################
# Adım 2: MariaDB Kurulumu ve Yapılandırması
###############################################################################
install_mariadb() {
    log_info "Adım 2: MariaDB kuruluyor..."
    
    # MariaDB kurulumu
    log_info "MariaDB paketleri kuruluyor..."
    dnf -y install mariadb mariadb-server
    
    # MariaDB servisini başlat ve etkinleştir
    log_info "MariaDB servisi başlatılıyor..."
    systemctl start mariadb
    systemctl enable mariadb
    
    # MariaDB güvenlik yapılandırması
    log_info "MariaDB güvenlik yapılandırması yapılıyor..."
    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    log_info "Adım 2 tamamlandı!"
}

###############################################################################
# Adım 3: PowerDNS Veritabanı Yapılandırması
###############################################################################
configure_powerdns_db() {
    log_info "Adım 3: PowerDNS veritabanı yapılandırılıyor..."
    
    # Veritabanı ve kullanıcı oluştur
    log_info "PowerDNS veritabanı ve kullanıcı oluşturuluyor..."
    mysql -u root -p${MYSQL_ROOT_PASS} <<EOF
CREATE DATABASE IF NOT EXISTS ${POWERDB_NAME};
CREATE USER IF NOT EXISTS '${POWERDB_USER}'@'localhost' IDENTIFIED BY '${POWERDB_PASS}';
GRANT ALL PRIVILEGES ON ${POWERDB_NAME}.* TO '${POWERDB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Veritabanı tablolarını oluştur
    log_info "PowerDNS veritabanı tabloları oluşturuluyor..."
    mysql -u root -p${MYSQL_ROOT_PASS} ${POWERDB_NAME} <<EOF
CREATE TABLE IF NOT EXISTS domains (
   id                    INT AUTO_INCREMENT,
   name                  VARCHAR(255) NOT NULL,
   master                VARCHAR(128) DEFAULT NULL,
   last_check            INT DEFAULT NULL,
   type                  VARCHAR(6) NOT NULL,
   notified_serial       INT DEFAULT NULL,
   account               VARCHAR(40) DEFAULT NULL,
   PRIMARY KEY (id)
) Engine=InnoDB;

CREATE UNIQUE INDEX IF NOT EXISTS name_index ON domains(name);

CREATE TABLE IF NOT EXISTS records (
   id                    BIGINT AUTO_INCREMENT,
   domain_id             INT DEFAULT NULL,
   name                  VARCHAR(255) DEFAULT NULL,
   type                  VARCHAR(10) DEFAULT NULL,
   content               VARCHAR(64000) DEFAULT NULL,
   ttl                   INT DEFAULT NULL,
   prio                  INT DEFAULT NULL,
   change_date           INT DEFAULT NULL,
   disabled              TINYINT(1) DEFAULT 0,
   ordername             VARCHAR(255) BINARY DEFAULT NULL,
   auth                  TINYINT(1) DEFAULT 1,
   PRIMARY KEY (id)
) Engine=InnoDB;

CREATE INDEX IF NOT EXISTS nametype_index ON records(name,type);
CREATE INDEX IF NOT EXISTS domain_id ON records(domain_id);
CREATE INDEX IF NOT EXISTS recordorder ON records (domain_id, ordername);

CREATE TABLE IF NOT EXISTS supermasters (
   ip                    VARCHAR(64) NOT NULL,
   nameserver            VARCHAR(255) NOT NULL,
   account               VARCHAR(40) NOT NULL,
   PRIMARY KEY (ip, nameserver)
) Engine=InnoDB;

CREATE TABLE IF NOT EXISTS comments (
   id                    INT AUTO_INCREMENT,
   domain_id             INT NOT NULL,
   name                  VARCHAR(255) NOT NULL,
   type                  VARCHAR(10) NOT NULL,
   modified_at           INT NOT NULL,
   account               VARCHAR(40) NOT NULL,
   comment               VARCHAR(64000) NOT NULL,
   PRIMARY KEY (id)
) Engine=InnoDB;

CREATE INDEX IF NOT EXISTS comments_domain_id_idx ON comments (domain_id);
CREATE INDEX IF NOT EXISTS comments_name_type_idx ON comments (name, type);
CREATE INDEX IF NOT EXISTS comments_order_idx ON comments (domain_id, modified_at);

CREATE TABLE IF NOT EXISTS domainmetadata (
   id                    INT AUTO_INCREMENT,
   domain_id             INT NOT NULL,
   kind                  VARCHAR(32),
   content               TEXT,
   PRIMARY KEY (id)
) Engine=InnoDB;

CREATE INDEX IF NOT EXISTS domainmetadata_idx ON domainmetadata (domain_id, kind);

CREATE TABLE IF NOT EXISTS cryptokeys (
   id                    INT AUTO_INCREMENT,
   domain_id             INT NOT NULL,
   flags                 INT NOT NULL,
   active                BOOLEAN,
   content               TEXT,
   PRIMARY KEY (id)
) Engine=InnoDB;

CREATE INDEX IF NOT EXISTS cryptokeys_domain_id_idx ON cryptokeys (domain_id);

CREATE TABLE IF NOT EXISTS tsigkeys (
   id                    INT AUTO_INCREMENT,
   name                  VARCHAR(255),
   algorithm             VARCHAR(50),
   secret                VARCHAR(255),
   PRIMARY KEY (id),
   UNIQUE KEY namealgoindex (name, algorithm)
) Engine=InnoDB;

CREATE TABLE IF NOT EXISTS users (
   id                    INT AUTO_INCREMENT,
   username              VARCHAR(64) NOT NULL,
   password              VARCHAR(128) NOT NULL,
   fullname              VARCHAR(255) NOT NULL,
   email                 VARCHAR(128) NOT NULL,
   description           TEXT,
   perm_templ            INT DEFAULT NULL,
   active                TINYINT(1) DEFAULT 1,
   PRIMARY KEY (id),
   UNIQUE KEY username (username)
) Engine=InnoDB;
EOF
    
    log_info "Adım 3 tamamlandı!"
}

###############################################################################
# Adım 4: PowerDNS Kurulumu
###############################################################################
install_powerdns() {
    log_info "Adım 4: PowerDNS kuruluyor..."
    
    # PowerDNS kurulumu
    log_info "PowerDNS paketleri kuruluyor..."
    dnf -y install pdns pdns-backend-mysql
    
    log_info "Adım 4 tamamlandı!"
}

###############################################################################
# Adım 5: PowerDNS Yapılandırması
###############################################################################
configure_powerdns() {
    log_info "Adım 5: PowerDNS yapılandırılıyor..."
    
    # PowerDNS yapılandırma dosyasını yedekle
    if [ -f /etc/pdns/pdns.conf ]; then
        cp /etc/pdns/pdns.conf /etc/pdns/pdns.conf.backup
    fi
    
    # PowerDNS yapılandırması
    log_info "PowerDNS yapılandırma dosyası oluşturuluyor..."
    cat > /etc/pdns/pdns.conf <<EOF
# PowerDNS Yapılandırması
launch=gmysql
gmysql-host=localhost
gmysql-user=${POWERDB_USER}
gmysql-password=${POWERDB_PASS}
gmysql-dbname=${POWERDB_NAME}
EOF
    
    # PowerDNS servisini başlat ve etkinleştir
    log_info "PowerDNS servisi başlatılıyor..."
    systemctl start pdns
    systemctl enable pdns
    
    # Firewall yapılandırması
    log_info "Firewall yapılandırılıyor..."
    firewall-cmd --permanent --add-service=dns
    firewall-cmd --reload
    
    # PowerDNS durumunu kontrol et
    if systemctl is-active --quiet pdns; then
        log_info "PowerDNS servisi başarıyla çalışıyor!"
    else
        log_error "PowerDNS servisi başlatılamadı!"
        exit 1
    fi
    
    log_info "Adım 5 tamamlandı!"
}

###############################################################################
# Adım 6: PowerAdmin Kurulumu
###############################################################################
install_poweradmin() {
    log_info "Adım 6: PowerAdmin kuruluyor..."
    
    # Apache ve PHP paketlerini kur
    log_info "Apache ve PHP paketleri kuruluyor..."
    dnf -y install httpd php php-cli php-common php-curl php-gd php-mysqlnd php-mbstring php-xml php-xmlrpc php-pear gettext
    
    # PHP PEAR DB kurulumu
    log_info "PHP PEAR DB kuruluyor..."
    pear install db || log_warn "PEAR DB kurulumu atlandı (zaten kurulu olabilir)"
    
    # Apache servisini başlat ve etkinleştir
    log_info "Apache servisi başlatılıyor..."
    systemctl start httpd
    systemctl enable httpd
    
    # PowerAdmin indirme
    log_info "PowerAdmin indiriliyor..."
    cd /var/www/html/
    
    if [ ! -f poweradmin-2.2.1.tar.gz ]; then
        wget -q https://sourceforge.net/projects/poweradmin/files/poweradmin-2.2.1.tar.gz
    fi
    
    # PowerAdmin dosyalarını çıkar ve doğrudan html klasörüne taşı
    log_info "PowerAdmin dosyaları çıkarılıyor..."
    if [ -f poweradmin-2.2.1.tar.gz ]; then
        # Geçici bir dizinde çıkar
        tar xvf poweradmin-2.2.1.tar.gz -C /tmp/
        rm -f poweradmin-2.2.1.tar.gz
        
        # PowerAdmin klasöründeki tüm dosyaları html klasörüne taşı
        if [ -d /tmp/poweradmin-2.2.1 ]; then
            log_info "PowerAdmin dosyaları /var/www/html/ klasörüne taşınıyor..."
            # Mevcut dosyaları korumak için önce kontrol et
            cp -r /tmp/poweradmin-2.2.1/* /var/www/html/
            # Geçici dizini temizle
            rm -rf /tmp/poweradmin-2.2.1
        fi
    fi
    
    # Dizin izinlerini ayarla
    log_info "Dizin izinleri ayarlanıyor..."
    chown -R apache:apache /var/www/html
    chmod -R 755 /var/www/html
    
    # Firewall yapılandırması
    log_info "HTTP/HTTPS firewall kuralları ekleniyor..."
    firewall-cmd --permanent --add-service={http,https}
    firewall-cmd --reload
    
    # Apache durumunu kontrol et
    if systemctl is-active --quiet httpd; then
        log_info "Apache servisi başarıyla çalışıyor!"
    else
        log_error "Apache servisi başlatılamadı!"
        exit 1
    fi
    
    log_info "Adım 6 tamamlandı!"
}


###############################################################################
# Özet Bilgileri Göster
###############################################################################
show_summary() {
    log_info "=========================================="
    log_info "Kurulum Tamamlandı!"
    log_info "=========================================="
    echo ""
    log_info "PowerDNS Durumu:"
    systemctl status pdns --no-pager -l || true
    echo ""
    log_info "Apache Durumu:"
    systemctl status httpd --no-pager -l || true
    echo ""
    log_info "PowerAdmin Web Arayüzü:"
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}http://${SERVER_IP}/install${NC}"
    echo ""
    log_info "Kurulum Bilgileri:"
    echo "  - Veritabanı: ${POWERDB_NAME}"
    echo "  - Veritabanı Kullanıcı: ${POWERDB_USER}"
    echo "  - Veritabanı Şifre: ${POWERDB_PASS}"
    echo "  - PowerAdmin Kullanıcı: ${POWERADMIN_USER}"
    echo "  - PowerAdmin Şifre: ${POWERADMIN_PASS}"
    echo "  - Hostmaster: ${HOSTMASTER}"
    echo "  - Nameserver: ${NAMESERVER}"
    echo ""
    log_warn "ÖNEMLİ:"
    echo "  1. Web tarayıcınızda http://${SERVER_IP}/install adresine gidin"
    echo "  2. Kurulum sihirbazında yukarıdaki veritabanı bilgilerini kullanın"
    echo "  3. PowerAdmin kullanıcı adı ve şifresini girin"
    echo "  4. Hostmaster ve Nameserver bilgilerini girin"
    echo "  5. Kurulum tamamlandıktan sonra /var/www/html/install dizinini silin"
    echo ""
}

###############################################################################
# Ana Fonksiyon
###############################################################################
main() {
    clear
    log_info "=========================================="
    log_info "PowerDNS ve PowerAdmin Kurulum Scripti"
    log_info "AlmaLinux 9 için"
    log_info "=========================================="
    echo ""
    
    check_root
    check_selinux
    get_user_input
    
    echo ""
    log_info "Kurulum başlatılıyor..."
    echo ""
    
    install_dependencies
    echo ""
    
    install_mariadb
    echo ""
    
    configure_powerdns_db
    echo ""
    
    install_powerdns
    echo ""
    
    configure_powerdns
    echo ""
    
    install_poweradmin
    echo ""
    
    show_summary
}

# Scripti çalıştır
main

