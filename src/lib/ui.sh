#!/bin/bash

# WPST Panel - UI Helper Functions
# Chứa các functions để hiển thị giao diện người dùng

# Terminal control
init_screen() {
    # Ẩn cursor khi không cần thiết
    tput civis 2>/dev/null || true
    
    # Đặt terminal về trạng thái bình thường khi thoát
    trap 'tput cnorm 2>/dev/null || true' EXIT
}

# Header functions
show_header() {
    local title="$1"
    local width=80
    
    echo -e "${BLUE}"
    printf '╔'
    printf '═%.0s' $(seq 1 $((width-2)))
    printf '╗\n'
    
    local title_len=${#title}
    local padding=$(( (width - title_len - 2) / 2 ))
    printf '║'
    printf ' %.0s' $(seq 1 $padding)
    printf "%s" "$title"
    printf ' %.0s' $(seq 1 $((width - title_len - padding - 2)))
    printf '║\n'
    
    printf '╚'
    printf '═%.0s' $(seq 1 $((width-2)))
    printf '╝\n'
    echo -e "${NC}"
}

show_ascii_logo() {
    echo -e "${CYAN}"
    cat << 'EOF'
 _    _ _____   _____ _______   _____                 _ 
| |  | |  __ \ / ____|__   __| |  __ \               | |
| |  | | |__) | (___    | |    | |__) |_ _ _ __   ___ | |
| |/\| |  ___/ \___ \   | |    |  ___/ _` | '_ \ / _ \| |
\  /\  / |     ____) |  | |    | |  | (_| | | | |  __/| |
 \/  \/|_|    |_____/   |_|    |_|   \__,_|_| |_|\___||_|

WordPress Stack Tool - Phiên bản 1.0.0
EOF
    echo -e "${NC}"
}

# Table functions
print_table_header() {
    local headers=("$@")
    local width=80
    
    echo -e "${BLUE}"
    printf '┌'
    for i in "${!headers[@]}"; do
        if [[ $i -eq 0 ]]; then
            printf '─%.0s' $(seq 1 20)
        else
            printf '┬'
            printf '─%.0s' $(seq 1 12)
        fi
    done
    printf '┐\n'
    
    printf '│'
    for i in "${!headers[@]}"; do
        if [[ $i -eq 0 ]]; then
            printf " %-18s │" "${headers[i]}"
        else
            printf " %-10s │" "${headers[i]}"
        fi
    done
    printf '\n'
    
    printf '├'
    for i in "${!headers[@]}"; do
        if [[ $i -eq 0 ]]; then
            printf '─%.0s' $(seq 1 20)
        else
            printf '┼'
            printf '─%.0s' $(seq 1 12)
        fi
    done
    printf '┤\n'
    echo -e "${NC}"
}

print_table_row() {
    local values=("$@")
    
    printf '│'
    for i in "${!values[@]}"; do
        local value="${values[i]}"
        
        # Truncate nếu quá dài
        if [[ $i -eq 0 ]]; then
            printf " %-18.18s │" "$value"
        else
            printf " %-10.10s │" "$value"
        fi
    done
    printf '\n'
}

print_table_footer() {
    local col_count="$1"
    
    echo -e "${BLUE}"
    printf '└'
    for i in $(seq 1 "$col_count"); do
        if [[ $i -eq 1 ]]; then
            printf '─%.0s' $(seq 1 20)
        else
            printf '┴'
            printf '─%.0s' $(seq 1 12)
        fi
    done
    printf '┘\n'
    echo -e "${NC}"
}

# Status indicators
show_status_indicator() {
    local status="$1"
    
    case "$status" in
        "online"|"running"|"active"|"enabled")
            echo -e "${GREEN}●${NC}"
            ;;
        "offline"|"stopped"|"inactive"|"disabled")
            echo -e "${RED}●${NC}"
            ;;
        "warning"|"degraded")
            echo -e "${YELLOW}●${NC}"
            ;;
        *)
            echo -e "${BLUE}●${NC}"
            ;;
    esac
}

show_yes_no() {
    local value="$1"
    
    if [[ "$value" == "true" || "$value" == "1" || "$value" == "yes" ]]; then
        echo -e "${GREEN}Có${NC}"
    else
        echo -e "${RED}Không${NC}"
    fi
}

# Progress bars
show_progress_bar() {
    local current="$1"
    local total="$2"
    local width="$3"
    local prefix="$4"
    
    local percentage=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    
    printf "%s [" "$prefix"
    printf "%*s" "$filled" | tr ' ' '█'
    printf "%*s" "$((width - filled))" | tr ' ' '░'
    printf "] %d%%\n" "$percentage"
}

# Info boxes
show_info_box() {
    local title="$1"
    local content="$2"
    local width=60
    
    echo -e "${BLUE}"
    printf '┌─ %s ' "$title"
    printf '─%.0s' $(seq 1 $((width - ${#title} - 4)))
    printf '┐\n'
    
    # Split content by lines
    while IFS= read -r line; do
        printf '│ %-*s │\n' $((width-4)) "$line"
    done <<< "$content"
    
    printf '└'
    printf '─%.0s' $(seq 1 $((width-2)))
    printf '┘\n'
    echo -e "${NC}"
}

show_warning_box() {
    local title="$1"
    local content="$2"
    
    echo -e "${YELLOW}"
    echo "⚠️  $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$content"
    echo -e "${NC}"
}

show_error_box() {
    local title="$1"
    local content="$2"
    
    echo -e "${RED}"
    echo "❌ $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$content"
    echo -e "${NC}"
}

show_success_box() {
    local title="$1"
    local content="$2"
    
    echo -e "${GREEN}"
    echo "✅ $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$content"
    echo -e "${NC}"
}

# Input helpers
show_menu_prompt() {
    local prompt="$1"
    local options=("${@:2}")
    
    echo -e "\n${CYAN}$prompt${NC}"
    for i in "${!options[@]}"; do
        echo "$((i+1)). ${options[i]}"
    done
    echo ""
    read -p "Lựa chọn: " choice
    echo "$choice"
}

show_confirmation() {
    local message="$1"
    local default="${2:-n}"
    
    echo -e "\n${YELLOW}$message${NC}"
    
    if [[ "$default" == "y" ]]; then
        read -p "Xác nhận [Y/n]: " confirm
        confirm=${confirm:-y}
    else
        read -p "Xác nhận [y/N]: " confirm
        confirm=${confirm:-n}
    fi
    
    case "$confirm" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Loading animations
show_spinner() {
    local message="$1"
    local duration="${2:-5}"
    
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    
    printf "%s " "$message"
    
    while [[ $i -lt $duration ]]; do
        printf "\r%s %s" "$message" "${chars:$((i % ${#chars})):1}"
        sleep 0.1
        ((i++))
    done
    
    printf "\r%s ✓\n" "$message"
}

show_loading_dots() {
    local message="$1"
    local duration="${2:-3}"
    
    printf "%s" "$message"
    
    for i in $(seq 1 "$duration"); do
        printf "."
        sleep 0.5
    done
    
    printf " ✓\n"
}

# System stats display helpers
format_uptime() {
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    local days=$((uptime_seconds / 86400))
    local hours=$(((uptime_seconds % 86400) / 3600))
    local minutes=$(((uptime_seconds % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

format_load_average() {
    local load=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
    echo "$load"
}

get_memory_usage() {
    local mem_info=$(free -m)
    local total=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local used=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local percentage=$(( used * 100 / total ))
    
    echo "${used}MB/${total}MB (${percentage}%)"
}

get_disk_usage() {
    local disk_info=$(df -h / | tail -1)
    local used=$(echo "$disk_info" | awk '{print $3}')
    local total=$(echo "$disk_info" | awk '{print $2}')
    local percentage=$(echo "$disk_info" | awk '{print $5}')
    
    echo "${used}/${total} (${percentage})"
}

# Quick info display
show_quick_stats() {
    local hostname=$(hostname)
    local ip=$(get_server_ip)
    local uptime=$(format_uptime)
    local load=$(format_load_average)
    local memory=$(get_memory_usage)
    local disk=$(get_disk_usage)
    
    echo -e "${CYAN}🖥️  Server: ${WHITE}$hostname${NC} | ${CYAN}📍 IP: ${WHITE}$ip${NC}"
    echo -e "${CYAN}⏱️  Uptime: ${WHITE}$uptime${NC} | ${CYAN}📊 Load: ${WHITE}$load${NC}"
    echo -e "${CYAN}💾 Memory: ${WHITE}$memory${NC} | ${CYAN}💿 Disk: ${WHITE}$disk${NC}"
}

# Cleanup screen
clear_screen() {
    clear
    tput cup 0 0
}

pause_for_input() {
    local message="${1:-Nhấn Enter để tiếp tục...}"
    echo ""
    read -p "$message"
}

# Export functions
export -f init_screen show_header show_ascii_logo
export -f print_table_header print_table_row print_table_footer
export -f show_status_indicator show_yes_no show_progress_bar
export -f show_info_box show_warning_box show_error_box show_success_box
export -f show_menu_prompt show_confirmation
export -f show_spinner show_loading_dots
export -f format_uptime format_load_average get_memory_usage get_disk_usage
export -f show_quick_stats clear_screen pause_for_input
