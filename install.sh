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
        
        log "Downloading FrankenPHP package..."
        cd /tmp
        if ! wget "$DOWNLOAD_URL" -O "$PACKAGE_NAME"; then
            error "Không thể download FrankenPHP package."
        fi
        
        log "Installing FrankenPHP package..."
        if ! dpkg -i "$PACKAGE_NAME"; then
            log "Fixing package dependencies..."
            apt install -f -y || error "Không thể fix package dependencies."
        fi
        
    elif [[ $OS == "rhel" ]]; then
        if [[ $ARCH_NAME == "amd64" ]]; then
            RPM_ARCH="x86_64"
        else
            RPM_ARCH="aarch64"
        fi
        PACKAGE_NAME="frankenphp-${VERSION_NUM}-1.${RPM_ARCH}.rpm"
        DOWNLOAD_URL="https://github.com/php/frankenphp/releases/download/${FRANKENPHP_VERSION}/${PACKAGE_NAME}"
        
        log "Downloading FrankenPHP package..."
        cd /tmp
        if ! wget "$DOWNLOAD_URL" -O "$PACKAGE_NAME"; then
            error "Không thể download FrankenPHP package."
        fi
        
        log "Installing FrankenPHP package..."
        if ! $PKG_MANAGER install -y "$PACKAGE_NAME"; then
            error "Không thể cài đặt FrankenPHP package."
        fi
    fi
    
    # Kiểm tra cài đặt
    log "Verifying FrankenPHP installation..."
    if ! command -v frankenphp >/dev/null 2>&1; then
        error "Cài đặt FrankenPHP thất bại - command không tìm thấy."
    fi
    
    # Kiểm tra version
    local installed_version=$(frankenphp version 2>/dev/null | head -1)
    if [[ -n "$installed_version" ]]; then
        log "FrankenPHP version: $installed_version"
    fi
    
    info "FrankenPHP đã được cài đặt thành công."
}

# Nhập email cho SSL (đã loại bỏ)
get_ssl_email() {
    log "Bỏ qua bước nhập email SSL..."
    SSL_EMAIL="admin@localhost"
    info "Sử dụng email mặc định: $SSL_EMAIL"
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
    
    # Tạo thư mục WPST nếu chưa có
    mkdir -p "$WPST_DIR"
    
    # Copy script chính từ thư mục hiện tại
    if [[ -f "src/wpst" ]]; then
        cp "src/wpst" "$WPST_DIR/wpst"
        chmod +x "$WPST_DIR/wpst"
        log "Đã copy script chính từ src/wpst"
    else
        # Tạo script placeholder nếu không có file gốc
        cat > "$WPST_DIR/wpst" << 'EOF'
#!/bin/bash
# WPST Panel - WordPress Stack Tool
# Phiên bản: 1.0.0

# Load common functions
source /var/www/wpst-script/lib/common.sh

# Main menu
show_main_menu() {
    clear
    show_ascii_logo
    echo ""
    show_quick_stats
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Quản lý Website"
    echo "2. Thông tin Hệ thống"
    echo "3. Cài đặt & Cấu hình"
    echo "4. Backup & Restore"
    echo "5. Logs & Monitoring"
    echo "0. Thoát"
    echo ""
    read -p "Lựa chọn: " choice
    
    case $choice in
        1) show_sites_menu ;;
        2) show_system_info ;;
        3) show_config_menu ;;
        4) show_backup_menu ;;
        5) show_logs_menu ;;
        0) echo "Tạm biệt!"; exit 0 ;;
        *) echo "Lựa chọn không hợp lệ."; sleep 1; show_main_menu ;;
    esac
}

# Placeholder functions
show_sites_menu() {
    echo "Quản lý Website - Đang phát triển..."
    sleep 2
    show_main_menu
}

show_system_info() {
    echo "Thông tin Hệ thống - Đang phát triển..."
    sleep 2
    show_main_menu
}

show_config_menu() {
    echo "Cài đặt & Cấu hình - Đang phát triển..."
    sleep 2
    show_main_menu
}

show_backup_menu() {
    echo "Backup & Restore - Đang phát triển..."
    sleep 2
    show_main_menu
}

show_logs_menu() {
    echo "Logs & Monitoring - Đang phát triển..."
    sleep 2
    show_main_menu
}

# Start the application
show_main_menu
EOF
        log "Đã tạo script placeholder"
    fi
    
    # Tạo symlink để có thể chạy từ bất kỳ đâu
    ln -sf "$WPST_DIR/wpst" /usr/local/bin/wpst
    
    # Copy thư mục lib nếu có
    if [[ -d "src/lib" ]]; then
        cp -r src/lib "$WPST_DIR/"
        log "Đã copy thư mục lib"
    else
        # Tạo thư mục lib cơ bản
        mkdir -p "$WPST_DIR/lib"
        log "Đã tạo thư mục lib"
    fi
    
    info "WPST Panel đã được cài đặt tại $WPST_DIR"
}

# Hiển thị thông tin hoàn thành
show_completion_info() {
    echo -e "\n${GREEN}🎉 WPST Panel Cài Đặt Hoàn Thành!${NC}\n"
    
    echo -e "${BLUE}✅ Thông Tin Hệ Thống:${NC}"
    echo -e "   FrankenPHP: $FRANKENPHP_VERSION đã cài đặt & chạy"
    echo -e "   MariaDB: $MARIADB_VERSION đã cài đặt & bảo mật"
    echo -e "   SSL: Tự động với Let's Encrypt"
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
    # Trap để handle Ctrl+C
    trap 'echo -e "\n${RED}Đã hủy cài đặt.${NC}"; exit 1' INT TERM
    
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
    
    # Thực hiện từng bước với error handling
    local step=1
    local total_steps=11
    
    log "Step $step/$total_steps: Kiểm tra quyền root..."
    check_root
    ((step++))
    
    log "Step $step/$total_steps: Phát hiện hệ thống..."
    detect_system
    ((step++))
    
    log "Step $step/$total_steps: Kiểm tra điều kiện tiên quyết..."
    check_prerequisites
    ((step++))
    
    log "Step $step/$total_steps: Cài đặt dependencies..."
    install_dependencies
    ((step++))
    
    log "Step $step/$total_steps: Cài đặt FrankenPHP..."
    install_frankenphp
    ((step++))
    
    log "Step $step/$total_steps: Cấu hình SSL..."
    get_ssl_email
    ((step++))
    
    log "Step $step/$total_steps: Chọn phiên bản MariaDB..."
    select_mariadb_version
    ((step++))
    
    log "Step $step/$total_steps: Cài đặt MariaDB..."
    install_mariadb
    ((step++))
    
    log "Step $step/$total_steps: Bảo mật MariaDB..."
    secure_mariadb
    ((step++))
    
    log "Step $step/$total_steps: Tạo cấu trúc thư mục..."
    create_directories
    ((step++))
    
    log "Step $step/$total_steps: Tạo cấu hình FrankenPHP..."
    create_frankenphp_config
    ((step++))
    
    log "Step $step/$total_steps: Khởi động dịch vụ..."
    start_services
    ((step++))
    
    log "Step $step/$total_steps: Cài đặt WPST script..."
    install_wpst_script
    
    show_completion_info
    
    log "Cài đặt hoàn thành thành công!"
}

# Chạy script chính
main "$@"
