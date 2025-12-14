# PowerDNS ve PowerAdmin Otomatik Kurulum Scripti

Bu script, AlmaLinux 9 üzerinde PowerDNS ve PowerAdmin'i otomatik olarak kurar ve yapılandırır.

## Gereksinimler

- AlmaLinux 9 işletim sistemi
- Root yetkisi
- İnternet bağlantısı
- SELinux devre dışı (önerilir)

## Kurulum

1. Scripti indirin ve çalıştırılabilir yapın:

```bash
chmod +x install-powerdns.sh
```

2. Scripti root yetkisi ile çalıştırın:

```bash
sudo ./install-powerdns.sh
```

## Kurulum Adımları

Script aşağıdaki adımları otomatik olarak gerçekleştirir:

1. **Sistem Güncellemesi ve Bağımlılıklar**
   - EPEL repository kurulumu
   - Remi repository kurulumu
   - PHP Remi 7.4 modülü etkinleştirme

2. **MariaDB Kurulumu**
   - MariaDB paketlerinin kurulumu
   - MariaDB servisinin başlatılması
   - Güvenlik yapılandırması

3. **PowerDNS Veritabanı Yapılandırması**
   - PowerDNS veritabanı oluşturma
   - Veritabanı kullanıcısı oluşturma
   - Gerekli tabloların oluşturulması

4. **PowerDNS Kurulumu**
   - PowerDNS paketlerinin kurulumu
   - MySQL backend kurulumu

5. **PowerDNS Yapılandırması**
   - PowerDNS yapılandırma dosyası oluşturma
   - Servis başlatma ve etkinleştirme
   - Firewall kuralları

6. **PowerAdmin Kurulumu**
   - Apache ve PHP paketlerinin kurulumu
   - PowerAdmin indirme ve kurulumu
   - Dizin izinlerinin ayarlanması
   - Firewall kuralları

## Kurulum Sırasında İstenen Bilgiler

Script çalıştırıldığında aşağıdaki bilgiler istenir:

- **MariaDB root şifresi**: MariaDB root kullanıcısı için şifre
- **PowerDNS veritabanı adı**: Varsayılan: `powerdb`
- **PowerDNS veritabanı kullanıcı adı**: Varsayılan: `poweruser`
- **PowerDNS veritabanı kullanıcı şifresi**: Veritabanı kullanıcısı için şifre
- **PowerAdmin yönetici şifresi**: PowerAdmin web arayüzü için şifre
- **PowerAdmin kullanıcı adı**: Varsayılan: `admin`
- **Hostmaster e-posta**: Varsayılan: `admin@example.com`
- **Nameserver**: Varsayılan: `ns1.example.com`

## Web Arayüzü Kurulumu

Script tamamlandıktan sonra:

1. Web tarayıcınızda aşağıdaki adrese gidin:
   ```
   http://<sunucu-ip-adresi>/install
   ```

2. Kurulum sihirbazını takip edin:
   - **Adım 1**: Dil seçimi
   - **Adım 2**: Bilgilendirme
   - **Adım 3**: Veritabanı bilgilerini girin (script tarafından oluşturulan)
   - **Adım 4**: PowerAdmin kullanıcı bilgilerini girin
   - **Adım 5**: MariaDB komutlarını çalıştırın (gösterilen komutları)
   - **Adım 6**: Config dosyasını yapılandırın
   - **Adım 7**: Kurulumu tamamlayın

3. Kurulum tamamlandıktan sonra install dizinini silin:
   ```bash
   rm -rf /var/www/html/install
   ```

## Servis Durumu Kontrolü

PowerDNS servis durumunu kontrol etmek için:

```bash
systemctl status pdns
```

Apache servis durumunu kontrol etmek için:

```bash
systemctl status httpd
```

## Güvenlik Notları

- Kurulum sonrası güçlü şifreler kullanın
- Firewall kurallarını gözden geçirin
- SELinux'u devre dışı bırakmak yerine uygun politikalar oluşturmayı düşünün
- Düzenli olarak sistem güncellemelerini yapın

## Sorun Giderme

### PowerDNS servisi başlamıyor

```bash
# Logları kontrol edin
journalctl -u pdns -n 50

# Yapılandırma dosyasını kontrol edin
cat /etc/pdns/pdns.conf
```

### Apache servisi başlamıyor

```bash
# Logları kontrol edin
journalctl -u httpd -n 50

# Apache yapılandırmasını test edin
httpd -t
```

### Veritabanı bağlantı hatası

```bash
# MariaDB servisini kontrol edin
systemctl status mariadb

# Veritabanı bağlantısını test edin
mysql -u poweruser -p powerdb
```
