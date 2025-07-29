#!/bin/bash

# WPST Panel - System Management Functions
# Chứa các functions để quản lý và hiển thị thông tin hệ thống

# System information functions
get_os_info() {
    local os_name=""
    local os_version=""
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os_name="$PRETTY_NAME"
        os_version="$VERSION_ID"
    elif [[ -f /etc/redhat-release ]]; then
        os_name=$(cat /etc/redhat-release)
    elif [[ -f /etc/debian_version ]]; then
        os_name="Debian $(cat /etc/debian_version)"
    else
        os_name="Unknown"
    fi
    
    echo "$os_name"
}

get_cpu_info() {
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//')
    local cpu_cores=$(nproc)
    
    echo "$cpu_model ($cpu_cores cores)"
}

get_kernel_version() {
    uname -r
}

get_architecture() {
    uname -m
}

# Memory and storage functions
get_total_memory() {
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))
    echo "${mem_mb}MB"
}

get_memory_stats() {
    local mem_info=$(free -m)
    local total=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local used=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local available=$(echo "$mem_info" | awk 'NR==2{print $7}')
    local percentage=$(( used * 100 / total ))
    
    echo "used:$used total:$total available:$available percentage:$percentage"
}

get_disk_stats() {
    local disk_info=$(df -BM / | tail -1)
    local total=$(echo "$disk_info" | awk '{print $2}' | sed 's/M//')
    local used=$(echo "$disk_info" | awk '{print $3}' | sed 's/M//')
    local available=$(echo "$disk_info" | awk '{print $4}' | sed 's/M//')
    local percentage=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
    
    echo "used:$used total:$total available:$available percentage:$percentage"
}

get_swap_stats() {
    local swap_info=$(free -m | grep Swap)
    if [[ -n "$swap_info" ]]; then
        local total=$(echo "$swap_info" | awk '{print $2}')
        local used=$(echo "$swap_info" | awk '{print $3}')
        
        if [[ $total -gt 0 ]]; then
            local percentage=$(( used * 100 / total ))
            echo "used:$used total:$total percentage:$percentage"
        else
            echo "used:0 total:0 percentage:0"
        fi
    else
        echo "used:0 total:0 percentage:0"
    fi
}

# Network functions
get_network_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo
}

get_network_stats() {
    local interface="$1"
    
    if [[ -z "$interface" ]]; then
        # Lấy interface chính
        interface=$(ip route | grep default | awk '{print $5}' | head -1)
    fi
    
    if [[ -n "$interface" && -f "/sys/class/net/$interface/statistics/rx_bytes" ]]; then
        local rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
        local tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes")
        
        local rx_mb=$((rx_bytes / 1024 / 1024))
        local tx_mb=$((tx_bytes / 1024 / 1024))
        
        echo "interface:$interface rx:${rx_mb}MB tx:${tx_mb}MB"
    else
        echo "interface:unknown rx:0MB tx:0MB"
    fi
}

# Service management functions
get_frankenphp_info() {
    local status="unknown"
    local version="unknown"
    local pid=""
    
    if command -v frankenphp >/dev/null 2>&1; then
        version=$(frankenphp version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' | head -1)
        
        if systemctl is-active --quiet frankenphp; then
            status="running"
            pid=$(systemctl show frankenphp --property=MainPID --value)
        elif systemctl is-enabled --quiet frankenphp 2>/dev/null; then
            status="stopped"
        else
            status="disabled"
        fi
    else
        status="not_installed"
    fi
    
    echo "status:$status version:$version pid:$pid"
}

get_mariadb_info() {
    local status="unknown"
    local version="unknown"
    local pid=""
    
    if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
        if command -v mariadb >/dev/null 2>&1; then
            version=$(mariadb --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        else
            version=$(mysql --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        fi
        
        if systemctl is-active --quiet mariadb; then
            status="running"
            pid=$(systemctl show mariadb --property=MainPID --value)
        elif systemctl is-active --quiet mysql; then
            status="running"
            pid=$(systemctl show mysql --property=MainPID --value)
        elif systemctl is-enabled --quiet mariadb 2>/dev/null; then
            status="stopped"
        elif systemctl is-enabled --quiet mysql 2>/dev/null; then
            status="stopped"
        else
            status="disabled"
        fi
    else
        status="not_installed"
    fi
    
    echo "status:$status version:$version pid:$pid"
}

# Process functions
get_top_processes() {
    local count="${1:-5}"
    ps aux --sort=-%cpu | head -n $((count + 1)) | tail -n $count
}

get_process_count() {
    ps aux | wc -l
}

# System load functions
get_load_averages() {
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | tr -d ' ')
    echo "$load_avg"
}

get_cpu_usage() {
    # Lấy CPU usage từ /proc/stat
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    echo "${cpu_usage:-0}%"
}

# Display functions for dashboard
show_system_stats() {
    echo -e "🖥️  Hostname: ${GREEN}$(hostname)${NC} | IP: ${GREEN}$(get_server_ip)${NC}"
    echo -e "⏱️   Uptime: ${GREEN}$(format_uptime)${NC} | Load: ${GREEN}$(get_load_averages)${NC}"
    
    # Memory info
    local mem_stats=$(get_memory_stats)
    local mem_used=$(echo "$mem_stats" | cut -d: -f2 | cut -d' ' -f1)
    local mem_total=$(echo "$mem_stats" | cut -d: -f3 | cut -d' ' -f1)
    local mem_percentage=$(echo "$mem_stats" | cut -d: -f5)
    
    # Disk info
    local disk_stats=$(get_disk_stats)
    local disk_used=$(echo "$disk_stats" | cut -d: -f2 | cut -d' ' -f1)
    local disk_total=$(echo "$disk_stats" | cut -d: -f3 | cut -d' ' -f1)
    local disk_percentage=$(echo "$disk_stats" | cut -d: -f5)
    
    echo -e "💾 Memory: ${GREEN}${mem_used}MB/${mem_total}MB${NC} (${mem_percentage}%) | Disk: ${GREEN}${disk_used}MB/${disk_total}MB${NC} (${disk_percentage}%)"
}

show_service_status() {
    echo -e "🔧 Dịch vụ:"
    
    # FrankenPHP status
    local frankenphp_info=$(get_frankenphp_info)
    local frankenphp_status=$(echo "$frankenphp_info" | cut -d: -f2 | cut -d' ' -f1)
    local frankenphp_version=$(echo "$frankenphp_info" | cut -d: -f3 | cut -d' ' -f1)
    
    case "$frankenphp_status" in
        "running")
            echo -e "   • FrankenPHP: $(show_status_indicator running) ${GREEN}Đang chạy${NC} ($frankenphp_version)"
            ;;
        "stopped")
            echo -e "   • FrankenPHP: $(show_status_indicator stopped) ${RED}Đã dừng${NC} ($frankenphp_version)"
            ;;
        "not_installed")
            echo -e "   • FrankenPHP: $(show_status_indicator stopped) ${RED}Chưa cài đặt${NC}"
            ;;
        *)
            echo -e "   • FrankenPHP: $(show_status_indicator warning) ${YELLOW}Không xác định${NC}"
            ;;
    esac
    
    # MariaDB status
    local mariadb_info=$(get_mariadb_info)
    local mariadb_status=$(echo "$mariadb_info" | cut -d: -f2 | cut -d' ' -f1)
    local mariadb_version=$(echo "$mariadb_info" | cut -d: -f3 | cut -d' ' -f1)
    
    case "$mariadb_status" in
        "running")
            echo -e "   • MariaDB: $(show_status_indicator running) ${GREEN}Đang chạy${NC} ($mariadb_version)"
            ;;
        "stopped")
            echo -e "   • MariaDB: $(show_status_indicator stopped) ${RED}Đã dừng${NC} ($mariadb_version)"
            ;;
        "not_installed")
            echo -e "   • MariaDB: $(show_status_indicator stopped) ${RED}Chưa cài đặt${NC}"
            ;;
        *)
            echo -e "   • MariaDB: $(show_status_indicator warning) ${YELLOW}Không xác định${NC}"
            ;;
    esac
}

# System maintenance functions
check_system_health() {
    local issues=()
    
    # Kiểm tra disk space
    local disk_stats=$(get_disk_stats)
    local disk_percentage=$(echo "$disk_stats" | cut -d: -f5)
    if [[ $disk_percentage -gt 90 ]]; then
        issues+=("Dung lượng đĩa cao ($disk_percentage%)")
    fi
    
    # Kiểm tra memory
    local mem_stats=$(get_memory_stats)
    local mem_percentage=$(echo "$mem_stats" | cut -d: -f5)
    if [[ $mem_percentage -gt 90 ]]; then
        issues+=("Sử dụng RAM cao ($mem_percentage%)")
    fi
    
    # Kiểm tra load average
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    local cpu_cores=$(nproc)
    local load_threshold=$((cpu_cores * 2))
    
    if (( $(echo "$load_1min > $load_threshold" | bc -l 2>/dev/null || echo "0") )); then
        issues+=("Load average cao ($load_1min)")
    fi
    
    # Kiểm tra services
    if ! systemctl is-active --quiet frankenphp; then
        issues+=("FrankenPHP không chạy")
    fi
    
    if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
        issues+=("MariaDB không chạy")
    fi
    
    # Trả về kết quả
    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "healthy"
    else
        printf '%s\n' "${issues[@]}"
    fi
}

get_system_uptime_seconds() {
    awk '{print int($1)}' /proc/uptime
}

# Log functions
get_system_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    if [[ -n "$service" ]]; then
        journalctl -u "$service" --no-pager -n "$lines" --output=short
    else
        journalctl --no-pager -n "$lines" --output=short
    fi
}

get_error_logs() {
    local lines="${1:-20}"
    journalctl -p err --no-pager -n "$lines" --output=short
}

# Update functions
check_system_updates() {
    if command -v apt >/dev/null 2>&1; then
        # Debian/Ubuntu
        apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0"
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora/RHEL 8+
        dnf check-update -q 2>/dev/null | wc -l || echo "0"
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS 7
        yum check-update -q 2>/dev/null | wc -l || echo "0"
    else
        echo "unknown"
    fi
}

# Export functions
export -f get_os_info get_cpu_info get_kernel_version get_architecture
export -f get_total_memory get_memory_stats get_disk_stats get_swap_stats
export -f get_network_interfaces get_network_stats
export -f get_frankenphp_info get_mariadb_info
export -f get_top_processes get_process_count
export -f get_load_averages get_cpu_usage
export -f show_system_stats show_service_status
export -f check_system_health get_system_uptime_seconds
export -f get_system_logs get_error_logs check_system_updates
