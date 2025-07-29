#!/bin/bash

# WPST Panel - Sites Management Functions
# Chứa các functions để quản lý websites

# Site listing and display functions
list_sites_table() {
    local sites=($(get_sites_list))
    
    if [[ ${#sites[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Chưa có website nào được tạo.${NC}"
        return
    fi
    
    # Table headers
    print_table_header "Domain" "Status" "Ping" "Backup" "Size" "Total"
    
    # Table rows
    for domain in "${sites[@]}"; do
        local status=$(get_site_status "$domain")
        local ping_status=$(check_site_ping "$domain")
        local backup_count=$(count_site_backups "$domain")
        local public_size=$(get_directory_size "$SITES_DIR/$domain/public")
        local total_size=$(get_directory_size "$SITES_DIR/$domain")
        
        # Format status
        local status_display
        if [[ "$status" == "online" ]]; then
            status_display="${GREEN}ON${NC}"
        else
            status_display="${RED}OFF${NC}"
        fi
        
        # Format ping
        local ping_display
        if [[ "$ping_status" == "success" ]]; then
            ping_display="${GREEN}✓${NC}"
        else
            ping_display="${RED}✗${NC}"
        fi
        
        print_table_row "$domain" "$status_display" "$ping_display" "$backup_count" "$public_size" "$total_size"
    done
    
    print_table_footer 6
}

# Site status functions
check_site_ping() {
    local domain="$1"
    local timeout=5
    
    # Kiểm tra HTTP/HTTPS
    if curl -s --max-time "$timeout" -I "https://$domain" >/dev/null 2>&1; then
        echo "success"
    elif curl -s --max-time "$timeout" -I "http://$domain" >/dev/null 2>&1; then
        echo "success"
    else
        echo "failed"
    fi
}

get_directory_size() {
    local dir="$1"
    
    if [[ -d "$dir" ]]; then
        local size_bytes=$(du -sb "$dir" 2>/dev/null | cut -f1)
        format_bytes "$size_bytes"
    else
        echo "0B"
    fi
}

count_site_backups() {
    local domain="$1"
    local backup_dir="$SITES_DIR/$domain/backup"
    
    if [[ -d "$backup_dir" ]]; then
        find "$backup_dir" -name "*.tar.gz" -type f 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

# Site detail display
show_site_details() {
    local domain="$1"
    local site_dir="$SITES_DIR/$domain"
    
    if [[ ! -d "$site_dir" ]]; then
        error "Website $domain không tồn tại."
        return 1
    fi
    
    # Ngày tạo
    local created_date="N/A"
    if [[ -f "$site_dir/.created" ]]; then
        created_date=$(cat "$site_dir/.created")
    elif [[ -d "$site_dir" ]]; then
        created_date=$(stat -c %y "$site_dir" | cut -d' ' -f1)
    fi
    
    echo -e "📅 Ngày thêm: ${GREEN}$created_date${NC}"
    echo -e "🌐 Domain: ${GREEN}$domain${NC}"
    
    # SSL info
    local ssl_info=$(get_ssl_info "$domain")
    echo -e "🔒 SSL: $ssl_info"
    
    # Storage info
    local public_size=$(get_directory_size "$site_dir/public")
    local total_size=$(get_directory_size "$site_dir")
    echo -e "💾 Dung lượng: Public ${GREEN}$public_size${NC} / Total ${GREEN}$total_size${NC}"
    
    # Status
    local status=$(get_site_status "$domain")
    if [[ "$status" == "online" ]]; then
        echo -e "🔴 Trạng thái: ${GREEN}Online${NC}"
    else
        echo -e "🔴 Trạng thái: ${RED}Offline${NC}"
    fi
    
    # Database info
    local db_info=$(get_site_database_info "$domain")
    echo -e "🗃️  Database: $db_info"
}

get_ssl_info() {
    local domain="$1"
    
    # Kiểm tra custom SSL
    if [[ -f "$SITES_DIR/$domain/ssl/cert.pem" ]]; then
        local expiry=$(openssl x509 -in "$SITES_DIR/$domain/ssl/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            echo -e "${BLUE}Custom${NC} (Hết hạn: $expiry)"
        else
            echo -e "${YELLOW}Custom (Không đọc được)${NC}"
        fi
    else
        # Kiểm tra Let's Encrypt
        local cert_path="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$domain"
        if [[ -f "$cert_path/$domain.crt" ]]; then
            local expiry=$(openssl x509 -in "$cert_path/$domain.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [[ -n "$expiry" ]]; then
                echo -e "${GREEN}Let's Encrypt${NC} (Hết hạn: $expiry)"
            else
                echo -e "${GREEN}Let's Encrypt${NC}"
            fi
        else
            echo -e "${YELLOW}Chưa có SSL${NC}"
        fi
    fi
}

get_site_database_info() {
    local domain="$1"
    local db_name=$(echo "$domain" | sed 's/\./_/g')_db
    
    if database_exists "$db_name"; then
        local db_size=$(get_database_size "$db_name")
        echo -e "${GREEN}$db_name${NC} ($db_size)"
    else
        echo -e "${RED}Chưa có database${NC}"
    fi
}

get_database_size() {
    local db_name="$1"
    load_db_config
    
    local size_bytes=$(mysql -u root -p"$DB_ROOT_PASSWORD" -e "
        SELECT ROUND(SUM(data_length + index_length), 1) AS 'DB Size in Bytes' 
        FROM information_schema.tables 
        WHERE table_schema='$db_name';" -s -N 2>/dev/null)
    
    if [[ -n "$size_bytes" && "$size_bytes" != "NULL" ]]; then
        format_bytes "$size_bytes"
    else
        echo "0B"
    fi
}

# Site creation functions
add_new_site() {
    clear
    show_header "Thêm Website Mới"
    
    # Nhập domain
    local domain
    while true; do
        echo -e "\n${BLUE}Nhập tên domain:${NC}"
        read -p "Domain: " domain
        domain=$(trim "$domain")
        
        # Validate domain format
        if ! validate_domain "$domain"; then
            warning "Domain không hợp lệ. Vui lòng nhập lại."
            continue
        fi
        
        # Kiểm tra trùng lặp
        if site_exists "$domain"; then
            warning "Domain $domain đã tồn tại. Vui lòng chọn domain khác."
            continue
        fi
        
        break
    done
    
    # Kiểm tra DNS
    info "Kiểm tra DNS pointing..."
    local server_ip=$(get_server_ip)
    
    if ! check_dns_pointing "$domain" "$server_ip"; then
        show_warning_box "DNS Chưa Trỏ Đúng" "Domain $domain chưa trỏ về IP $server_ip.\nNếu sử dụng Cloudflare, vui lòng tạm thời tắt Proxy.\nBạn có thể tiếp tục nhưng SSL có thể không hoạt động."
        
        if ! read_confirm "Bạn có muốn tiếp tục?" "n"; then
            return
        fi
    else
        success "Domain $domain đã trỏ đúng về IP $server_ip"
    fi
    
    # Kiểm tra conflict thư mục
    if [[ -d "$SITES_DIR/$domain" ]]; then
        error "Thư mục $SITES_DIR/$domain đã tồn tại. Vui lòng xóa trong Quản lý website trước."
        return 1
    fi
    
    # Xác nhận tạo database
    local create_database="y"
    echo -e "\n${BLUE}Tạo database cho website này?${NC}"
    read -p "Tạo database [Y/n]: " create_db_input
    create_database=${create_db_input:-y}
    
    # Xác nhận cài WordPress
    local install_wordpress
    while true; do
        echo -e "\n${BLUE}Cài đặt WordPress?${NC}"
        read -p "Cài WordPress [y/N]: " install_wordpress
        case "$install_wordpress" in
            [Yy]*) install_wordpress="y"; break ;;
            [Nn]*|"") install_wordpress="n"; break ;;
            *) warning "Vui lòng nhập y hoặc n." ;;
        esac
    done
    
    # Bắt đầu quá trình tạo site
    info "Bắt đầu tạo website $domain..."
    
    # Tạo site với rollback support
    if create_site_with_rollback "$domain" "$create_database" "$install_wordpress"; then
        show_site_creation_summary "$domain"
    else
        error "Tạo website thất bại."
    fi
}

create_site_with_rollback() {
    local domain="$1"
    local create_database="$2"
    local install_wordpress="$3"
    
    local rollback_steps=()
    
    # Step 1: Tạo thư mục
    info "Tạo cấu trúc thư mục..."
    local site_dir="$SITES_DIR/$domain"
    
    mkdir -p "$site_dir"/{public,ssl,backup,logs}
    rollback_steps+=("rm -rf $site_dir")
    
    # Lưu ngày tạo
    date '+%Y-%m-%d %H:%M:%S' > "$site_dir/.created"
    
    # Step 2: Tạo database nếu cần
    local db_name=""
    local db_user=""
    local db_password=""
    
    if [[ "$create_database" == "y" ]]; then
        info "Tạo database..."
        
        db_name=$(echo "$domain" | sed 's/\./_/g')_db
        db_user=$(echo "$domain" | sed 's/\./_/g')_user
        db_password=$(generate_password 16)
        
        if ! create_site_database "$db_name" "$db_user" "$db_password"; then
            rollback_site_creation "${rollback_steps[@]}"
            return 1
        fi
        
        rollback_steps+=("drop_site_database $db_name $db_user")
    fi
    
    # Step 3: Cài WordPress nếu cần
    if [[ "$install_wordpress" == "y" ]]; then
        info "Tải và cài đặt WordPress..."
        
        if ! install_wordpress_for_site "$domain" "$db_name" "$db_user" "$db_password"; then
            rollback_site_creation "${rollback_steps[@]}"
            return 1
        fi
    else
        # Tạo index.php đơn giản
        cat > "$site_dir/public/index.php" << EOF
<?php
echo "<h1>Website $domain</h1>";
echo "<p>Website đã được tạo thành công!</p>";
echo "<p>Bạn có thể upload code của mình vào thư mục public.</p>";
?>
EOF
    fi
    
    # Step 4: Tạo Caddyfile
    info "Tạo cấu hình Caddy..."
    
    if ! create_site_caddyfile "$domain"; then
        rollback_site_creation "${rollback_steps[@]}"
        return 1
    fi
    
    # Step 5: Reload FrankenPHP
    info "Khởi động lại FrankenPHP..."
    
    if ! restart_service frankenphp; then
        rollback_site_creation "${rollback_steps[@]}"
        return 1
    fi
    
    # Set permissions
    chown -R frankenphp:frankenphp "$site_dir"
    chmod -R 755 "$site_dir"
    chmod -R 644 "$site_dir/public"
    
    success "Website $domain đã được tạo thành công!"
    return 0
}

rollback_site_creation() {
    local steps=("$@")
    
    warning "Đang rollback do có lỗi xảy ra..."
    
    # Thực hiện rollback theo thứ tự ngược lại
    for ((i=${#steps[@]}-1; i>=0; i--)); do
        local step="${steps[i]}"
        info "Rollback: $step"
        
        if [[ "$step" == rm* ]]; then
            eval "$step" 2>/dev/null || true
        elif [[ "$step" == drop_site_database* ]]; then
            local args=($step)
            drop_site_database "${args[1]}" "${args[2]}"
        fi
    done
    
    warning "Rollback hoàn thành."
}

create_site_database() {
    local db_name="$1"
    local db_user="$2"
    local db_password="$3"
    
    load_db_config
    
    # Tạo database
    if ! mysql_query "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        error "Không thể tạo database $db_name"
        return 1
    fi
    
    # Tạo user
    if ! mysql_query "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_password';"; then
        error "Không thể tạo user $db_user"
        mysql_query "DROP DATABASE \`$db_name\`;" 2>/dev/null
        return 1
    fi
    
    # Cấp quyền
    if ! mysql_query "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';"; then
        error "Không thể cấp quyền cho user $db_user"
        mysql_query "DROP USER '$db_user'@'localhost';" 2>/dev/null
        mysql_query "DROP DATABASE \`$db_name\`;" 2>/dev/null
        return 1
    fi
    
    mysql_query "FLUSH PRIVILEGES;"
    
    return 0
}

drop_site_database() {
    local db_name="$1"
    local db_user="$2"
    
    load_db_config
    
    mysql_query "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null
    mysql_query "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null
    mysql_query "FLUSH PRIVILEGES;" 2>/dev/null
}

install_wordpress_for_site() {
    local domain="$1"
    local db_name="$2"
    local db_user="$3"
    local db_password="$4"
    
    local site_dir="$SITES_DIR/$domain"
    local public_dir="$site_dir/public"
    
    # Download WordPress
    cd /tmp
    
    if ! wget -q https://wordpress.org/latest.tar.gz; then
        error "Không thể tải WordPress"
        return 1
    fi
    
    # Extract
    if ! tar -xzf latest.tar.gz; then
        error "Không thể giải nén WordPress"
        rm -f latest.tar.gz
        return 1
    fi
    
    # Copy files
    cp -r wordpress/* "$public_dir/"
    rm -rf wordpress latest.tar.gz
    
    # Tạo wp-config.php
    if [[ -n "$db_name" ]]; then
        create_wp_config "$public_dir" "$db_name" "$db_user" "$db_password"
    fi
    
    return 0
}

create_wp_config() {
    local public_dir="$1"
    local db_name="$2"
    local db_user="$3"
    local db_password="$4"
    
    # Generate WordPress salts
    local salts=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    
    cat > "$public_dir/wp-config.php" << EOF
<?php
// ** Database settings ** //
define( 'DB_NAME', '$db_name' );
define( 'DB_USER', '$db_user' );
define( 'DB_PASSWORD', '$db_password' );
define( 'DB_HOST', '127.0.0.1' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

// ** Authentication Unique Keys and Salts ** //
$salts

// ** WordPress Database Table prefix ** //
\$table_prefix = 'wp_';

// ** WordPress debugging mode ** //
define( 'WP_DEBUG', false );

// ** Security ** //
define( 'DISALLOW_FILE_EDIT', true );
define( 'AUTOMATIC_UPDATER_DISABLED', true );

// ** Absolute path to the WordPress directory ** //
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

// ** Sets up WordPress vars and included files ** //
require_once ABSPATH . 'wp-settings.php';
EOF
}

create_site_caddyfile() {
    local domain="$1"
    local site_dir="$SITES_DIR/$domain"
    
    # Detect www vs non-www
    local main_domain="$domain"
    local redirect_domain=""
    
    if [[ "$domain" == www.* ]]; then
        redirect_domain="$domain"
        main_domain="${domain#www.}"
    else
        redirect_domain="www.$domain"
    fi
    
    cat > "$site_dir/Caddyfile" << EOF
# Auto-redirect www <-> non-www
$redirect_domain {
    redir https://$main_domain{uri} permanent
}

$main_domain {
    root * $site_dir/public
    encode zstd gzip
    php_server
    
    # Security headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        Permissions-Policy "geolocation=(), microphone=(), camera=()"
        -Server
    }
    
    # Logging
    log {
        output file $site_dir/logs/access.log {
            roll_size 100mb
            roll_keep 5
            roll_keep_for 720h
        }
    }
    
    # WordPress specific rules
    @blocked {
        path *.txt *.log *.conf
        path /wp-admin/install.php
        path /wp-content/uploads/*.php
    }
    respond @blocked 403
}
EOF
    
    return 0
}

show_site_creation_summary() {
    local domain="$1"
    local site_dir="$SITES_DIR/$domain"
    
    echo ""
    show_success_box "Website Tạo Thành Công!" "Website $domain đã được tạo và cấu hình."
    
    echo -e "\n${BLUE}📋 THÔNG TIN WEBSITE${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "🌐 Website: ${GREEN}https://$domain${NC}"
    echo -e "📁 Thư mục: ${GREEN}$site_dir${NC}"
    
    # Database info nếu có
    local db_name=$(echo "$domain" | sed 's/\./_/g')_db
    if database_exists "$db_name"; then
        local db_user=$(echo "$domain" | sed 's/\./_/g')_user
        
        echo ""
        echo -e "${BLUE}🗃️  THÔNG TIN DATABASE${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "Database: ${GREEN}$db_name${NC}"
        echo -e "User: ${GREEN}$db_user${NC}"
        
        # Lưu thông tin database
        if [[ -f "$CONFIG_DIR/mariadb_root.conf" ]]; then
            source "$CONFIG_DIR/mariadb_root.conf"
            local db_password=$(mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT authentication_string FROM mysql.user WHERE User='$db_user' AND Host='localhost';" -s -N 2>/dev/null)
            if [[ -n "$db_password" ]]; then
                echo -e "Password: ${GREEN}Đã lưu trong hệ thống${NC}"
            fi
        fi
    fi
    
    echo ""
    pause_for_input
}

# Site toggle functions
toggle_site_status() {
    local domain="$1"
    local current_status=$(get_site_status "$domain")
    
    if [[ "$current_status" == "online" ]]; then
        disable_site "$domain"
    else
        enable_site "$domain"
    fi
    
    restart_service frankenphp
    show_single_site_dashboard "$domain"
}

disable_site() {
    local domain="$1"
    local site_dir="$SITES_DIR/$domain"
    
    if [[ -f "$site_dir/Caddyfile" ]]; then
        mv "$site_dir/Caddyfile" "$site_dir/Caddyfile.disabled"
        success "Website $domain đã được tắt."
    else
        warning "Website $domain đã được tắt từ trước."
    fi
}

enable_site() {
    local domain="$1"
    local site_dir="$SITES_DIR/$domain"
    
    if [[ -f "$site_dir/Caddyfile.disabled" ]]; then
        mv "$site_dir/Caddyfile.disabled" "$site_dir/Caddyfile"
        success "Website $domain đã được bật."
    else
        warning "Website $domain đã được bật từ trước."
    fi
}

# Site deletion
delete_site() {
    local domain="$1"
    
    clear
    show_header "Xóa Website: $domain"
    
    show_warning_box "CẢNH BÁO" "Bạn sắp xóa hoàn toàn website $domain.\nTất cả dữ liệu bao gồm files và database sẽ bị xóa vĩnh viễn!"
    
    echo -e "\n${RED}Để xác nhận, vui lòng gõ chính xác tên domain:${NC}"
    read -p "Nhập '$domain' để xác nhận: " confirm_domain
    
    if [[ "$confirm_domain" != "$domain" ]]; then
        warning "Domain không khớp. Hủy xóa website."
        sleep 2
        return
    fi
    
    if ! read_confirm "Bạn có chắc chắn muốn xóa website $domain?" "n"; then
        info "Đã hủy xóa website."
        sleep 1
        return
    fi
    
    # Thực hiện xóa
    info "Đang xóa website $domain..."
    
    # Xóa database
    local db_name=$(echo "$domain" | sed 's/\./_/g')_db
    local db_user=$(echo "$domain" | sed 's/\./_/g')_user
    
    if database_exists "$db_name"; then
        drop_site_database "$db_name" "$db_user"
        success "Đã xóa database $db_name"
    fi
    
    # Xóa thư mục
    if [[ -d "$SITES_DIR/$domain" ]]; then
        rm -rf "$SITES_DIR/$domain"
        success "Đã xóa thư mục website"
    fi
    
    # Restart FrankenPHP
    restart_service frankenphp
    
    show_success_box "Xóa Thành Công" "Website $domain đã được xóa hoàn toàn."
    
    pause_for_input
    show_sites_dashboard
}

# Placeholder functions cho các tính năng sẽ implement sau
edit_caddyfile() {
    local domain="$1"
    echo "Chỉnh sửa Caddyfile cho $domain - đang phát triển..."
    pause_for_input
    show_single_site_dashboard "$domain"
}

setup_custom_ssl() {
    local domain="$1"
    echo "Cài đặt SSL thủ công cho $domain - đang phát triển..."
    pause_for_input
    show_single_site_dashboard "$domain"
}

open_file_manager() {
    local domain="$1"
    echo "File Manager cho $domain - đang phát triển..."
    pause_for_input
    show_single_site_dashboard "$domain"
}

manage_database() {
    local domain="$1"
    echo "Quản lý Database cho $domain - đang phát triển..."
    pause_for_input
    show_single_site_dashboard "$domain"
}

backup_restore_site() {
    local domain="$1"
    echo "Backup & Restore cho $domain - đang phát triển..."
    pause_for_input
    show_single_site_dashboard "$domain"
}

# Export functions
export -f list_sites_table check_site_ping get_directory_size count_site_backups
export -f show_site_details get_ssl_info get_site_database_info get_database_size
export -f add_new_site create_site_with_rollback rollback_site_creation
export -f create_site_database drop_site_database install_wordpress_for_site
export -f create_wp_config create_site_caddyfile show_site_creation_summary
export -f toggle_site_status disable_site enable_site delete_site
export -f edit_caddyfile setup_custom_ssl open_file_manager manage_database backup_restore_site
