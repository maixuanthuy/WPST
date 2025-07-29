#!/bin/bash

# WPST Panel - Common Functions Library
# Chứa các functions dùng chung trong toàn bộ hệ thống

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Đường dẫn cấu hình
WPST_DIR="/var/www/wpst-script"
SITES_DIR="/var/www/sites"
CONFIG_DIR="$WPST_DIR/config"
LOG_DIR="$WPST_DIR/logs"

# Logging functions
log() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp]${NC} $message" | tee -a "$LOG_DIR/wpst.log"
}

error() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[LỖI]${NC} $message" | tee -a "$LOG_DIR/wpst.log"
    exit 1
}

warning() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[CẢNH BÁO]${NC} $message" | tee -a "$LOG_DIR/wpst.log"
}

info() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[THÔNG TIN]${NC} $message" | tee -a "$LOG_DIR/wpst.log"
}

success() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[THÀNH CÔNG]${NC} $message" | tee -a "$LOG_DIR/wpst.log"
}

# Validation functions
validate_domain() {
    local domain="$1"
    
    # Kiểm tra format domain
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    
    # Kiểm tra độ dài
    if [[ ${#domain} -gt 253 ]]; then
        return 1
    fi
    
    return 0
}

validate_email() {
    local email="$1"
    
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# File và directory functions
ensure_directory() {
    local dir="$1"
    local owner="$2"
    local perms="$3"
    
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
    
    if [[ -n "$owner" ]]; then
        chown "$owner" "$dir"
    fi
    
    if [[ -n "$perms" ]]; then
        chmod "$perms" "$dir"
    fi
}

backup_file() {
    local file="$1"
    local backup_suffix="${2:-_backup}"
    
    if [[ -f "$file" ]]; then
        cp "$file" "${file}${backup_suffix}"
        info "File đã được backup: $file -> ${file}${backup_suffix}"
    fi
}

# String functions
trim() {
    local var="$*"
    # Xóa khoảng trắng đầu và cuối
    var="${var#"${var%%[![:space:]]*}"}"   # Xóa đầu
    var="${var%"${var##*[![:space:]]}"}"   # Xóa cuối
    echo "$var"
}

generate_password() {
    local length="${1:-16}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# System functions
get_server_ip() {
    # Lấy IP public của server
    local ip
    ip=$(curl -s -4 ifconfig.me) 2>/dev/null
    if [[ -z "$ip" ]]; then
        ip=$(curl -s -4 ipinfo.io/ip) 2>/dev/null
    fi
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}

check_dns_pointing() {
    local domain="$1"
    local server_ip="$2"
    
    if [[ -z "$server_ip" ]]; then
        server_ip=$(get_server_ip)
    fi
    
    # Kiểm tra A record
    local resolved_ip
    resolved_ip=$(dig +short "$domain" | tail -n1)
    
    if [[ "$resolved_ip" == "$server_ip" ]]; then
        return 0
    else
        return 1
    fi
}

# Service functions
is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service"
}

get_service_status() {
    local service="$1"
    
    if systemctl is-active --quiet "$service"; then
        echo "running"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

restart_service() {
    local service="$1"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if systemctl restart "$service"; then
            success "Dịch vụ $service đã được khởi động lại."
            return 0
        else
            warning "Lần thử $attempt/$max_attempts khởi động lại $service thất bại."
            ((attempt++))
            sleep 2
        fi
    done
    
    error "Không thể khởi động lại dịch vụ $service sau $max_attempts lần thử."
}

# Database functions
load_db_config() {
    if [[ -f "$CONFIG_DIR/mariadb_root.conf" ]]; then
        source "$CONFIG_DIR/mariadb_root.conf"
    else
        error "Không tìm thấy cấu hình database."
    fi
}

mysql_query() {
    local query="$1"
    load_db_config
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "$query" 2>/dev/null
}

database_exists() {
    local db_name="$1"
    load_db_config
    mysql -u root -p"$DB_ROOT_PASSWORD" -e "USE $db_name;" 2>/dev/null
    return $?
}

user_exists() {
    local username="$1"
    load_db_config
    local count=$(mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM mysql.user WHERE User='$username';" -s -N 2>/dev/null)
    [[ "$count" -gt 0 ]]
}

# Site functions
get_sites_list() {
    local sites=()
    if [[ -d "$SITES_DIR" ]]; then
        for site_dir in "$SITES_DIR"/*; do
            if [[ -d "$site_dir" ]]; then
                sites+=($(basename "$site_dir"))
            fi
        done
    fi
    echo "${sites[@]}"
}

count_sites() {
    local sites=($(get_sites_list))
    echo "${#sites[@]}"
}

site_exists() {
    local domain="$1"
    [[ -d "$SITES_DIR/$domain" ]]
}

get_site_status() {
    local domain="$1"
    
    if [[ -f "$SITES_DIR/$domain/Caddyfile" ]]; then
        echo "online"
    elif [[ -f "$SITES_DIR/$domain/Caddyfile.disabled" ]]; then
        echo "offline"
    else
        echo "unknown"
    fi
}

# Format functions
format_bytes() {
    local bytes="$1"
    
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(( bytes / 1073741824 ))GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(( bytes / 1024 ))KB"
    else
        echo "${bytes}B"
    fi
}

format_percentage() {
    local used="$1"
    local total="$2"
    
    if [[ "$total" -eq 0 ]]; then
        echo "0%"
    else
        local percentage=$(( used * 100 / total ))
        echo "${percentage}%"
    fi
}

# Progress functions
show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    local width=50
    
    local percentage=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    
    printf "\r$message ["
    printf "%*s" "$filled" | tr ' ' '█'
    printf "%*s" "$((width - filled))" | tr ' ' '░'
    printf "] %d%%" "$percentage"
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# Input functions
read_confirm() {
    local message="$1"
    local default="${2:-n}"
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$message [Y/n]: " yn
            yn=${yn:-y}
        else
            read -p "$message [y/N]: " yn
            yn=${yn:-n}
        fi
        
        case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) warning "Vui lòng nhập y hoặc n." ;;
        esac
    done
}

read_input() {
    local prompt="$1"
    local default="$2"
    local value
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " value
        echo "${value:-$default}"
    else
        read -p "$prompt: " value
        echo "$value"
    fi
}

# Cleanup function
cleanup() {
    # Xóa các file tạm nếu có
    rm -f /tmp/wpst_*.tmp 2>/dev/null || true
    
    # Reset cursor nếu cần
    tput cnorm 2>/dev/null || true
}

# Khởi tạo hệ thống
init_system() {
    # Đảm bảo các thư mục cần thiết tồn tại
    ensure_directory "$LOG_DIR" "root:root" "755"
    ensure_directory "$CONFIG_DIR" "root:root" "700"
    
    # Tạo log file nếu chưa có
    if [[ ! -f "$LOG_DIR/wpst.log" ]]; then
        touch "$LOG_DIR/wpst.log"
        chmod 644 "$LOG_DIR/wpst.log"
    fi
}

# Xuất các functions để sử dụng
export -f log error warning info success
export -f validate_domain validate_email
export -f ensure_directory backup_file
export -f trim generate_password
export -f get_server_ip check_dns_pointing
export -f is_service_running get_service_status restart_service
export -f load_db_config mysql_query database_exists user_exists
export -f get_sites_list count_sites site_exists get_site_status
export -f format_bytes format_percentage
export -f show_progress
export -f read_confirm read_input
export -f cleanup init_system
