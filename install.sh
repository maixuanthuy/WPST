#!/bin/bash

# WPST Panel - WordPress Stack Tool Installer
# Phiên bản: 1.0.0
# Tác giả: WPST Team

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Biến toàn cục
WPST_DIR="/var/www/wpst-script"
SITES_DIR="/var/www/sites"
LOG_FILE="/tmp/wpst-install.log"

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[LỖI]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[CẢNH BÁO]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[THÔNG TIN]${NC} $1" | tee -a "$LOG_FILE"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Script này cần chạy với quyền root. Vui lòng chạy: sudo $0"
    fi
}

# Detect OS và Architecture
detect_system() {
    log "Đang phát hiện hệ điều hành..."
    
    # Detect OS
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        if grep -q "Ubuntu" /etc/os-release; then
            OS_NAME="Ubuntu"
        else
            OS_NAME="Debian"
        fi
        PKG_MANAGER="apt"
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        if grep -q "CentOS" /etc/redhat-release; then
            OS_NAME="CentOS"
        elif grep -q "Rocky" /etc/redhat-release; then
            OS_NAME="Rocky Linux"
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS_NAME="RHEL"
        else
            OS_NAME="RHEL-based"
        fi
        PKG_MANAGER="yum"
        if command -v dnf >/dev/null 2>&1; then
            PKG_MANAGER="dnf"
        fi
    else
        error "Hệ điều hành không được hỗ trợ. Chỉ hỗ trợ Debian/Ubuntu và RHEL/CentOS/Rocky Linux."
    fi
    
    # Detect Architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH_NAME="amd64"
            ;;
        aarch64)
            ARCH_NAME="arm64"
            ;;
        *)
            error "Kiến trúc CPU không được hỗ trợ: $ARCH"
            ;;
    esac
    
    info "Hệ điều hành: $OS_NAME ($OS)"
    info "Kiến trúc: $ARCH ($ARCH_NAME)"
    info "Trình quản lý gói: $PKG_MANAGER"
}

# Kiểm tra điều kiện tiên quyết
check_prerequisites() {
    log "Kiểm tra điều kiện tiên quyết..."
    
    # Kiểm tra kết nối internet
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error "Không có kết nối internet. Vui lòng kiểm tra kết nối mạng."
    fi
    
    # Kiểm tra dung lượng đĩa (tối thiểu 2GB)
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_SPACE -lt 2097152 ]]; then # 2GB in KB
        error "Cần ít nhất 2GB dung lượng trống. Hiện tại chỉ có $(($AVAILABLE_SPACE/1024/1024))GB."
    fi
    
    # Kiểm tra MySQL/MariaDB đã cài
    if command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1; then
        error "Phát hiện MySQL/MariaDB đã được cài đặt. WPST Panel không thể cài đặt khi đã có database server."
    fi
    
    info "Tất cả điều kiện tiên quyết đều đạt yêu cầu."
}

# Cài đặt dependencies
install_dependencies() {
    log "Cài đặt các gói phụ thuộc..."
    
    if [[ $OS == "debian" ]]; then
        apt update
        apt install -y curl wget gnupg2 software-properties-common lsb-release ca-certificates apt-transport-https dirmngr
    elif [[ $OS == "rhel" ]]; then
        $PKG_MANAGER update -y
        $PKG_MANAGER install -y curl wget gnupg2 ca-certificates
    fi
}

# Lấy phiên bản FrankenPHP mới nhất
get_frankenphp_version() {
    log "Lấy thông tin phiên bản FrankenPHP mới nhất..."
    
    FRANKENPHP_VERSION=$(curl -s https://api.github.com/repos/php/frankenphp/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [[ -z "$FRANKENPHP_VERSION" ]]; then
        error "Không thể lấy thông tin phiên bản FrankenPHP."
    fi
    
    info "Phiên bản FrankenPHP mới nhất: $FRANKENPHP_VERSION"
}

# Cài đặt FrankenPHP
install_frankenphp() {
    log "Cài đặt FrankenPHP..."
    
    get_frankenphp_version
    
    # Tạo URL download
    VERSION_NUM=${FRANKENPHP_VERSION#v} # Bỏ chữ 'v' đầu
    if [[ $OS == "debian" ]]; then
        PACKAGE_NAME="frankenphp_${VERSION_NUM}-1_${ARCH_NAME}.deb"
        DOWNLOAD_URL="https://github.com/php/frankenphp/releases/download/${FRANKENPHP_VERSION}/${PACKAGE_NAME}"
        
        cd /tmp
        wget "$DOWNLOAD_URL" -O "$PACKAGE_NAME"
        dpkg -i "$PACKAGE_NAME" || apt install -f -y
        
    elif [[ $OS == "rhel" ]]; then
        if [[ $ARCH_NAME == "amd64" ]]; then
            RPM_ARCH="x86_64"
        else
            RPM_ARCH="aarch64"
        fi
        PACKAGE_NAME="frankenphp-${VERSION_NUM}-1.${RPM_ARCH}.rpm"
        DOWNLOAD_URL="https://github.com/php/frankenphp/releases/download/${FRANKENPHP_VERSION}/${PACKAGE_NAME}"
        
        cd /tmp
        wget "$DOWNLOAD_URL" -O "$PACKAGE_NAME"
        $PKG_MANAGER install -y "$PACKAGE_NAME"
    fi
    
    # Kiểm tra cài đặt
    if ! command -v frankenphp >/dev/null 2>&1; then
        error "Cài đặt FrankenPHP thất bại."
    fi
    
    info "FrankenPHP đã được cài đặt thành công."
}

# Nhập email cho SSL
get_ssl_email() {
    while true; do
        echo -e "\n${BLUE}Nhập email để cấu hình SSL tự động (Let's Encrypt):${NC}"
        read -p "Email: " SSL_EMAIL
        
        # Validate email
        if [[ $SSL_EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            info "Email hợp lệ: $SSL_EMAIL"
            break
        else
            warning "Email không hợp lệ. Vui lòng nhập lại."
        fi
    done
}

# Chọn phiên bản MariaDB
select_mariadb_version() {
    echo -e "\n${BLUE}Chọn phiên bản MariaDB:${NC}"
    echo "1. MariaDB 10.11 (LTS - Khuyến nghị)"
    echo "2. MariaDB 11.8 (Stable)"
    
    while true; do
        read -p "Lựa chọn (1-2): " MARIADB_CHOICE
        case $MARIADB_CHOICE in
            1)
                MARIADB_VERSION="10.11"
                break
                ;;
            2)
                MARIADB_VERSION="11.8"
                break
                ;;
            *)
                warning "Lựa chọn không hợp lệ. Vui lòng chọn 1 hoặc 2."
                ;;
        esac
    done
    
    info "Đã chọn MariaDB $MARIADB_VERSION"
}

# Cài đặt MariaDB
install_mariadb() {
    log "Cài đặt MariaDB $MARIADB_VERSION..."
    
    if [[ $OS == "debian" ]]; then
        # Add MariaDB repository
        curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor -o /usr/share/keyrings/mariadb-keyring.gpg
        
        OS_CODENAME=$(lsb_release -cs)
        echo "deb [signed-by=/usr/share/keyrings/mariadb-keyring.gpg] https://mariadb.mirror.liquidtelecom.com/repo/$MARIADB_VERSION/debian $OS_CODENAME main" > /etc/apt/sources.list.d/mariadb.list
        
        apt update
        DEBIAN_FRONTEND=noninteractive apt install -y mariadb-server mariadb-client
        
    elif [[ $OS == "rhel" ]]; then
        # Add MariaDB repository
        cat > /etc/yum.repos.d/MariaDB.repo << EOF
[mariadb]
name = MariaDB
baseurl = https://mariadb.mirror.liquidtelecom.com/repo/$MARIADB_VERSION/rhel/\$releasever/\$basearch
gpgkey = https://mariadb.org/mariadb_release_signing_key.asc
gpgcheck = 1
EOF
        
        $PKG_MANAGER install -y MariaDB-server MariaDB-client
    fi
    
    # Start và enable MariaDB
    systemctl start mariadb
    systemctl enable mariadb
    
    info "MariaDB $MARIADB_VERSION đã được cài đặt và khởi động."
}

# Secure MariaDB installation
secure_mariadb() {
    log "Cấu hình bảo mật MariaDB..."
    
    # Generate random root password
    DB_ROOT_PASSWORD=$(openssl rand -base64 32)
    
    # Set root password
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';"
    
    # Remove anonymous users
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';"
    
    # Remove remote root
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    
    # Remove test database
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS test;"
    
    # Reload privileges
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
    
    # Save root password
    mkdir -p "$WPST_DIR/config"
    echo "DB_ROOT_PASSWORD=\"$DB_ROOT_PASSWORD\"" > "$WPST_DIR/config/mariadb_root.conf"
    chmod 600 "$WPST_DIR/config/mariadb_root.conf"
    chown root:root "$WPST_DIR/config/mariadb_root.conf"
    
    info "MariaDB đã được cấu hình bảo mật."
}

# Tạo cấu trúc thư mục
create_directories() {
    log "Tạo cấu trúc thư mục..."
    
    mkdir -p "$WPST_DIR"/{bin,lib,templates,config,logs}
    mkdir -p "$SITES_DIR"
    
    # Set permissions
    chown -R frankenphp:frankenphp /var/www
    chmod 755 /var/www
    chmod 755 "$SITES_DIR"
    
    info "Cấu trúc thư mục đã được tạo."
}

# Tạo cấu hình FrankenPHP
create_frankenphp_config() {
    log "Tạo cấu hình FrankenPHP..."
    
    # Backup original configs
    if [[ -f /etc/frankenphp/Caddyfile ]]; then
        cp /etc/frankenphp/Caddyfile /etc/frankenphp/Caddyfile_backup
    fi
    
    if [[ -f /etc/frankenphp/php.ini ]]; then
        cp /etc/frankenphp/php.ini /etc/frankenphp/php.ini_backup
    fi
    
    # Create main Caddyfile
    cat > /etc/frankenphp/Caddyfile << EOF
{
    frankenphp
    email $SSL_EMAIL
    trusted_proxies 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22 2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
}

# Import site configurations
import $SITES_DIR/*/Caddyfile
EOF

    # Create optimized php.ini
    cat > /etc/frankenphp/php.ini << 'EOF'
; ########### CẤU HÌNH CƠ BẢN ###########
memory_limit = 256M
max_execution_time = 300
max_input_time = 300
date.timezone = Asia/Ho_Chi_Minh

; ########### UPLOAD FILES ###########
upload_max_filesize = 256M
post_max_size = 512M
max_file_uploads = 20
max_input_vars = 10000

; ########### OPCODE CACHE ###########
opcache.enable=1
opcache.memory_consumption=512
opcache.interned_strings_buffer=128
opcache.max_accelerated_files=50000
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.fast_shutdown=1
opcache.enable_cli=0
opcache.jit=1254
opcache.jit_buffer_size=128M
opcache.save_comments=0
opcache.enable_file_override=1

; ########### REALPATH CACHE ###########
realpath_cache_size = 32M
realpath_cache_ttl = 300

; ########### WORDPRESS OPTIMIZATION ###########
disable_functions = exec,passthru,shell_exec,system
expose_php = Off

; ########### SESSION & CONCURRENT ###########
session.save_handler = files
session.save_path = "/tmp"
session.gc_probability = 1
session.gc_divisor = 100
EOF

    # Set permissions
    chown frankenphp:frankenphp /etc/frankenphp/Caddyfile
    chown frankenphp:frankenphp /etc/frankenphp/php.ini
    chmod 644 /etc/frankenphp/Caddyfile
    chmod 644 /etc/frankenphp/php.ini
    
    info "Cấu hình FrankenPHP đã được tạo."
}

# Start services
start_services() {
    log "Khởi động các dịch vụ..."
    
    systemctl restart frankenphp
    systemctl enable frankenphp
    
    if systemctl is-active --quiet frankenphp; then
        info "FrankenPHP đã được khởi động thành công."
    else
        error "Không thể khởi động FrankenPHP."
    fi
}

# Cài đặt WPST script chính
install_wpst_script() {
    log "Cài đặt WPST Panel..."
    
    # Download và cài đặt script chính (sẽ implement sau)
    # Hiện tại tạo placeholder
    cat > /usr/local/bin/wpst << 'EOF'
#!/bin/bash
echo "WPST Panel - Đang phát triển..."
echo "Chạy từ: /var/www/wpst-script"
EOF
    
    chmod +x /usr/local/bin/wpst
    
    info "WPST Panel đã được cài đặt."
}

# Hiển thị thông tin hoàn thành
show_completion_info() {
    echo -e "\n${GREEN}🎉 WPST Panel Cài Đặt Hoàn Thành!${NC}\n"
    
    echo -e "${BLUE}✅ Thông Tin Hệ Thống:${NC}"
    echo -e "   FrankenPHP: $FRANKENPHP_VERSION đã cài đặt & chạy"
    echo -e "   MariaDB: $MARIADB_VERSION đã cài đặt & bảo mật"
    echo -e "   SSL Email: $SSL_EMAIL đã cấu hình cho Let's Encrypt"
    echo -e "   Panel Location: $WPST_DIR"
    echo -e "   Sites Directory: $SITES_DIR"
    
    echo -e "\n${BLUE}📋 Bước Tiếp Theo:${NC}"
    echo -e "   1. Chạy: ${GREEN}wpst${NC} (để mở panel)"
    echo -e "   2. Tạo website đầu tiên"
    echo -e "   3. Cấu hình firewall trong panel"
    
    echo -e "\n${BLUE}🔐 Thông Tin Quan Trọng:${NC}"
    echo -e "   Mật khẩu MariaDB root đã được lưu an toàn"
    echo -e "   Log cài đặt: $LOG_FILE"
    
    echo -e "\n${GREEN}Cảm ơn bạn đã sử dụng WPST Panel!${NC}"
}

# Main installation process
main() {
    echo -e "${BLUE}"
    cat << 'EOF'
 _    _ _____   _____ _______   _____                 _ 
| |  | |  __ \ / ____|__   __| |  __ \               | |
| |  | | |__) | (___    | |    | |__) |_ _ _ __   ___ | |
| |/\| |  ___/ \___ \   | |    |  ___/ _` | '_ \ / _ \| |
\  /\  / |     ____) |  | |    | |  | (_| | | | |  __/| |
 \/  \/|_|    |_____/   |_|    |_|   \__,_|_| |_|\___||_|

WordPress Stack Tool - Phiên bản 1.0.0
EOF
    echo -e "${NC}\n"
    
    log "Bắt đầu cài đặt WPST Panel..."
    
    check_root
    detect_system
    check_prerequisites
    install_dependencies
    install_frankenphp
    get_ssl_email
    select_mariadb_version
    install_mariadb
    secure_mariadb
    create_directories
    create_frankenphp_config
    start_services
    install_wpst_script
    
    show_completion_info
    
    log "Cài đặt hoàn thành thành công!"
}

# Chạy script chính
main "$@"
