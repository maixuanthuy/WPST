#!/bin/bash

# WPST Panel - WordPress Stack Tool Installer
# Phiên bản: 1.0.0
# Tác giả: WPST Team

set -eE

# Trap function để handle lỗi
error_handler() {
    local line_num=$1
    echo -e "${RED}[LỖI]${NC} Script bị lỗi tại dòng $line_num" >&2
    echo -e "${RED}[LỖI]${NC} Quá trình cài đặt bị gián đoạn." >&2
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Biến toàn cục
WPST_DIR="/opt/wpst"
SITES_DIR="/var/www"
LOG_FILE="/tmp/wpst-install.log"
MARIADB_VERSION="11.8"

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

success() {
    echo -e "${GREEN}[THÀNH CÔNG]${NC} $1" | tee -a "$LOG_FILE"
}

progress() {
    echo -e "${CYAN}[TIẾN TRÌNH]${NC} $1" | tee -a "$LOG_FILE"
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
            OS_VERSION=$(grep "VERSION_ID" /etc/os-release | cut -d'"' -f2)
        else
            OS_NAME="Debian"
            OS_VERSION=$(cat /etc/debian_version)
        fi
        PKG_MANAGER="apt"
    else
        error "Hệ điều hành không được hỗ trợ. Chỉ hỗ trợ Debian/Ubuntu."
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
    
    info "Hệ điều hành: $OS_NAME $OS_VERSION ($OS)"
    info "Kiến trúc: $ARCH ($ARCH_NAME)"
    info "Trình quản lý gói: $PKG_MANAGER"
}

# Kiểm tra server hiện tại
check_server_status() {
    log "Kiểm tra trạng thái server..."
    
    local conflicts=()
    local warnings=()
    
    # Kiểm tra FrankenPHP
    if command -v frankenphp >/dev/null 2>&1; then
        local fp_version=$(frankenphp version 2>/dev/null | head -1 || echo "Unknown")
        warnings+=("FrankenPHP đã cài đặt: $fp_version (sẽ cài đè)")
    fi
    
    # Kiểm tra MariaDB/MySQL
    if command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1; then
        conflicts+=("MariaDB/MySQL đã được cài đặt")
    fi
    
    # Kiểm tra thư mục WPST
    if [[ -d "$WPST_DIR" ]]; then
        warnings+=("Thư mục WPST đã tồn tại: $WPST_DIR (sẽ ghi đè)")
    fi
    
    # Kiểm tra kết nối internet
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        conflicts+=("Không có kết nối internet")
    fi
    
    # Kiểm tra dung lượng đĩa (tối thiểu 2GB)
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_SPACE -lt 2097152 ]]; then # 2GB in KB
        conflicts+=("Cần ít nhất 2GB dung lượng trống. Hiện tại chỉ có $(($AVAILABLE_SPACE/1024/1024))GB")
    fi
    
    # Hiển thị tóm tắt
    echo -e "\n${PURPLE}📋 TÓM TẮT SERVER:${NC}"
    echo -e "   Hệ điều hành: ${GREEN}$OS_NAME $OS_VERSION${NC}"
    echo -e "   Kiến trúc: ${GREEN}$ARCH ($ARCH_NAME)${NC}"
    echo -e "   Dung lượng trống: ${GREEN}$(($AVAILABLE_SPACE/1024/1024))GB${NC}"
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠️  CẢNH BÁO:${NC}"
        for warning in "${warnings[@]}"; do
            echo -e "   • $warning"
        done
    fi
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo -e "\n${RED}❌ XUNG ĐỘT:${NC}"
        for conflict in "${conflicts[@]}"; do
            echo -e "   • $conflict"
        done
        echo -e "\n${RED}WPST Panel yêu cầu server sạch (không có MariaDB/MySQL).${NC}"
        echo -e "${RED}Vui lòng gỡ cài đặt MariaDB/MySQL trước khi tiếp tục.${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}✅ Server đã sẵn sàng cho việc cài đặt!${NC}"
}

# Xác nhận cài đặt
confirm_installation() {
    echo -e "\n${BLUE}🚀 CHUẨN BỊ CÀI ĐẶT WPST PANEL${NC}"
    echo -e "   Các dịch vụ sẽ được cài đặt:"
    echo -e "   • FrankenPHP (Web Server + PHP)"
    echo -e "   • MariaDB $MARIADB_VERSION (Database)"
    echo -e "   • WPST Panel (Management Tool)"
    echo -e "   • SSL tự động với Let's Encrypt"
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠️  Lưu ý:${NC}"
        for warning in "${warnings[@]}"; do
            echo -e "   • $warning"
        done
    fi
    
    echo -e "\n${CYAN}Bạn có muốn tiếp tục cài đặt không? (y/N):${NC} "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cài đặt đã bị hủy.${NC}"
        exit 0
    fi
    
    echo -e "\n${GREEN}Bắt đầu cài đặt...${NC}\n"
}

# Cài đặt dependencies
install_dependencies() {
    progress "Cài đặt các gói phụ thuộc..."
    
    apt update >/dev/null 2>&1
    apt install -y curl wget gnupg2 software-properties-common lsb-release ca-certificates apt-transport-https dirmngr >/dev/null 2>&1
    
    success "Dependencies đã được cài đặt"
}

# Lấy phiên bản FrankenPHP mới nhất
get_frankenphp_version() {
    progress "Lấy thông tin phiên bản FrankenPHP..."
    
    FRANKENPHP_VERSION=$(curl -s https://api.github.com/repos/php/frankenphp/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [[ -z "$FRANKENPHP_VERSION" ]]; then
        error "Không thể lấy thông tin phiên bản FrankenPHP."
    fi
    
    info "Phiên bản FrankenPHP: $FRANKENPHP_VERSION"
}

# Cài đặt FrankenPHP
install_frankenphp() {
    progress "Cài đặt FrankenPHP $FRANKENPHP_VERSION..."
    
    get_frankenphp_version
    
    # Tạo URL download
    VERSION_NUM=${FRANKENPHP_VERSION#v} # Bỏ chữ 'v' đầu
    PACKAGE_NAME="frankenphp_${VERSION_NUM}-1_${ARCH_NAME}.deb"
    DOWNLOAD_URL="https://github.com/php/frankenphp/releases/download/${FRANKENPHP_VERSION}/${PACKAGE_NAME}"
    
    progress "Tải FrankenPHP package..."
    cd /tmp
    if ! wget "$DOWNLOAD_URL" -O "$PACKAGE_NAME" >/dev/null 2>&1; then
        error "Không thể tải FrankenPHP package."
    fi
    
    progress "Cài đặt FrankenPHP package..."
    if ! dpkg -i "$PACKAGE_NAME" >/dev/null 2>&1; then
        progress "Sửa dependencies..."
        apt install -f -y >/dev/null 2>&1 || error "Không thể sửa package dependencies."
    fi
    
    # Kiểm tra cài đặt
    if ! command -v frankenphp >/dev/null 2>&1; then
        error "Cài đặt FrankenPHP thất bại."
    fi
    
    success "FrankenPHP đã được cài đặt"
}

# Cài đặt MariaDB
install_mariadb() {
    progress "Cài đặt MariaDB $MARIADB_VERSION..."
    
    # Add MariaDB repository
    curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc | gpg --dearmor -o /usr/share/keyrings/mariadb-keyring.gpg >/dev/null 2>&1
    
    OS_CODENAME=$(lsb_release -cs)
    
    # Xử lý riêng cho Ubuntu và Debian
    if [[ $OS_NAME == "Ubuntu" ]]; then
        echo "deb [signed-by=/usr/share/keyrings/mariadb-keyring.gpg] https://mariadb.mirror.liquidtelecom.com/repo/$MARIADB_VERSION/ubuntu $OS_CODENAME main" > /etc/apt/sources.list.d/mariadb.list
    else
        echo "deb [signed-by=/usr/share/keyrings/mariadb-keyring.gpg] https://mariadb.mirror.liquidtelecom.com/repo/$MARIADB_VERSION/debian $OS_CODENAME main" > /etc/apt/sources.list.d/mariadb.list
    fi
    
    apt update >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt install -y mariadb-server mariadb-client >/dev/null 2>&1
    
    # Start và enable MariaDB
    systemctl start mariadb >/dev/null 2>&1
    systemctl enable mariadb >/dev/null 2>&1
    
    success "MariaDB đã được cài đặt và khởi động"
}

# Secure MariaDB installation
secure_mariadb() {
    progress "Cấu hình bảo mật MariaDB..."
    
    # Generate random root password
    DB_ROOT_PASSWORD=$(openssl rand -base64 32)
    
    # Set root password
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';" >/dev/null 2>&1
    
    # Remove anonymous users
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';" >/dev/null 2>&1
    
    # Remove remote root
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" >/dev/null 2>&1
    
    # Remove test database
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS test;" >/dev/null 2>&1
    
    # Reload privileges
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" >/dev/null 2>&1
    
    # Save root password
    mkdir -p "$WPST_DIR/config"
    echo "DB_ROOT_PASSWORD=\"$DB_ROOT_PASSWORD\"" > "$WPST_DIR/config/mariadb_root.conf"
    chmod 600 "$WPST_DIR/config/mariadb_root.conf"
    chown root:root "$WPST_DIR/config/mariadb_root.conf"
    
    success "MariaDB đã được cấu hình bảo mật"
}

# Tạo cấu trúc thư mục
create_directories() {
    progress "Tạo cấu trúc thư mục..."
    
    mkdir -p "$WPST_DIR"/{bin,lib,templates,config,logs}
    
    # Set permissions
    chown -R frankenphp:frankenphp /var/www >/dev/null 2>&1
    chmod 755 /var/www
    
    success "Cấu trúc thư mục đã được tạo"
}

# Tạo cấu hình FrankenPHP
create_frankenphp_config() {
    progress "Tạo cấu hình FrankenPHP..."
    
    # Backup original configs
    if [[ -f /etc/frankenphp/Caddyfile ]]; then
        cp /etc/frankenphp/Caddyfile /etc/frankenphp/Caddyfile_backup
    fi
    
    if [[ -f /etc/frankenphp/php.ini ]]; then
        cp /etc/frankenphp/php.ini /etc/frankenphp/php.ini_backup
    fi
    
    # Create main Caddyfile
    cat > /etc/frankenphp/Caddyfile << 'EOF'
{
	frankenphp {
		num_threads auto
		max_threads auto
		max_wait_time 10
	}
}

import /var/www/*/Caddyfile
EOF

    # Create optimized php.ini
    cat > /etc/frankenphp/php.ini << 'EOF'
; ########### CẤU HÌNH CƠ BẢN ###########
memory_limit = 128M
max_execution_time = 300
max_input_time = 300
default_socket_timeout = 120
date.timezone = Asia/Ho_Chi_Minh

; ########### UPLOAD FILES ###########
upload_max_filesize = 128M
post_max_size = 256M
max_file_uploads = 10
max_input_vars = 20000
file_uploads = On

; ########### OUTPUT & BUFFER ###########
output_buffering = 4096
implicit_flush = Off
zlib.output_compression = On
zlib.output_compression_level = 6

; ########### SESSION ###########
session.save_handler = files
session.save_path = "/tmp"
session.gc_probability = 1
session.gc_divisor = 1000
session.gc_maxlifetime = 1440
session.cookie_httponly = On
session.cookie_secure = Off
session.use_strict_mode = On
session.cookie_samesite = "Lax"

; ########### OPCODE CACHE (QUAN TRỌNG) ###########
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=4000
opcache.max_wasted_percentage=10
opcache.validate_timestamps=1
opcache.revalidate_freq=5
opcache.fast_shutdown=1
opcache.enable_cli=0
opcache.jit=1254
opcache.jit_buffer_size=32M
opcache.save_comments=0
opcache.file_update_protection=2
opcache.huge_code_pages=0
opcache.preload_user = frankenphp

; ########### REALPATH CACHE ###########
realpath_cache_size = 16M
realpath_cache_ttl = 600

; ########### WORDPRESS OPTIMIZATION ###########
disable_functions = exec,passthru,shell_exec,system
expose_php = Off
allow_url_fopen = On
allow_url_include = Off
enable_dl = Off
cgi.fix_pathinfo = 0

; ########### DATABASE ###########
mysqli.max_persistent = 10
mysqli.max_links = 20
mysqli.default_port = 3306
mysqli.reconnect = Off

; ########### PERFORMANCE TUNING ###########
max_input_nesting_level = 64
pcre.backtrack_limit = 1000000
pcre.recursion_limit = 100000

; ########### WORDPRESS SPECIFIC ###########
user_ini.filename = ".user.ini"
user_ini.cache_ttl = 300

; ########### APCU ###########
apc.shm_size = 128M
EOF

    # Set permissions
    chown frankenphp:frankenphp /etc/frankenphp/Caddyfile
    chown frankenphp:frankenphp /etc/frankenphp/php.ini
    chmod 644 /etc/frankenphp/Caddyfile
    chmod 644 /etc/frankenphp/php.ini
    
    success "Cấu hình FrankenPHP đã được tạo"
}

# Start services
start_services() {
    progress "Khởi động các dịch vụ..."
    
    # Start FrankenPHP
    if ! systemctl restart frankenphp >/dev/null 2>&1; then
        error "Không thể khởi động FrankenPHP service."
    fi
    
    systemctl enable frankenphp >/dev/null 2>&1
    
    if systemctl is-active --quiet frankenphp; then
        success "FrankenPHP đã được khởi động"
    else
        error "FrankenPHP service không hoạt động."
    fi
}

# Cài đặt WPST script chính
install_wpst_script() {
    progress "Cài đặt WPST Panel..."
    
    # Tạo thư mục WPST nếu chưa có
    mkdir -p "$WPST_DIR"
    
    # Tải WPST script từ GitHub
    if ! curl -fsSL "https://raw.githubusercontent.com/maixuanthuy/wpst/main/src/wpst" -o "$WPST_DIR/wpst" >/dev/null 2>&1; then
        error "Không thể tải WPST script từ GitHub."
    fi
    chmod +x "$WPST_DIR/wpst"
    
    # Tạo symlink để có thể chạy từ bất kỳ đâu
    ln -sf "$WPST_DIR/wpst" /usr/local/bin/wpst
    
    # Tải thư mục lib từ GitHub
    mkdir -p "$WPST_DIR/lib"
    
    # Tải các file trong lib
    local lib_files=("adminneo.php" "tinyfilemanager.php" "8g-caddy.snippet")
    for file in "${lib_files[@]}"; do
        if ! curl -fsSL "https://raw.githubusercontent.com/maixuanthuy/wpst/main/src/lib/$file" -o "$WPST_DIR/lib/$file" >/dev/null 2>&1; then
            warning "Không thể tải file $file từ GitHub."
        fi
    done
    
    # Đảm bảo quyền cho lib files
    if [[ -d "$WPST_DIR/lib" ]]; then
        chown -R frankenphp:frankenphp "$WPST_DIR/lib"
        find "$WPST_DIR/lib" -type f -exec chmod 644 {} \;
        find "$WPST_DIR/lib" -type d -exec chmod 755 {} \;
    fi
    
    success "WPST Panel đã được cài đặt"
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
 ########                                         
##########        ##########       ###########    
###########      ############     ############### 
###########     ##############   #################
 ###########    ###############  #################
 ###########    ###############  ######      #####
  ###########   ######## ####### ######      #####
  ###########  ######### ####### ###### ##########
   ########### ######### ####### ###### ######### 
    ########## #########  ###### ###### #1.0.0   
    ########## ########   #############           
     ##################    ###########            
      ################      #########             
       ##############         ####                
          #########
EOF
    echo -e "${NC}\n"
    
    log "Bắt đầu cài đặt WPST Panel..."
    
    # Thực hiện từng bước với error handling
    check_root
    detect_system
    check_server_status
    confirm_installation
    
    echo -e "${CYAN}🔄 Đang cài đặt...${NC}\n"
    
    install_dependencies
    install_frankenphp
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
main
