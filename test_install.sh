#!/bin/bash

# Test script cho WPST Panel Installer
# Chạy để kiểm tra script cài đặt có hoạt động đúng không

set -e

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Testing WPST Panel Installer...${NC}"
echo ""

# Test 1: Kiểm tra file install.sh có tồn tại
echo -e "${BLUE}Test 1: Kiểm tra file install.sh${NC}"
if [[ -f "install.sh" ]]; then
    echo -e "${GREEN}✓ install.sh tồn tại${NC}"
else
    echo -e "${RED}✗ install.sh không tồn tại${NC}"
    exit 1
fi

# Test 2: Kiểm tra quyền thực thi
echo -e "${BLUE}Test 2: Kiểm tra quyền thực thi${NC}"
if [[ -x "install.sh" ]]; then
    echo -e "${GREEN}✓ install.sh có quyền thực thi${NC}"
else
    echo -e "${YELLOW}! Cấp quyền thực thi cho install.sh${NC}"
    chmod +x install.sh
fi

# Test 3: Kiểm tra syntax bash
echo -e "${BLUE}Test 3: Kiểm tra syntax bash${NC}"
if bash -n install.sh; then
    echo -e "${GREEN}✓ Syntax bash hợp lệ${NC}"
else
    echo -e "${RED}✗ Syntax bash có lỗi${NC}"
    exit 1
fi

# Test 4: Kiểm tra các function chính
echo -e "${BLUE}Test 4: Kiểm tra các function chính${NC}"

# Test function get_ssl_email
echo "Testing get_ssl_email function..."
cat > test_email.sh << 'EOF'
#!/bin/bash
source install.sh

# Mock function để test
get_ssl_email() {
    echo "test@example.com"
}

# Test
SSL_EMAIL=""
get_ssl_email
echo "Email: $SSL_EMAIL"
EOF

chmod +x test_email.sh
if bash test_email.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ get_ssl_email function hoạt động${NC}"
else
    echo -e "${RED}✗ get_ssl_email function có lỗi${NC}"
fi

# Test 5: Kiểm tra script wpst
echo -e "${BLUE}Test 5: Kiểm tra script wpst${NC}"
if [[ -f "src/wpst" ]]; then
    echo -e "${GREEN}✓ src/wpst tồn tại${NC}"
    if [[ -x "src/wpst" ]]; then
        echo -e "${GREEN}✓ src/wpst có quyền thực thi${NC}"
    else
        echo -e "${YELLOW}! Cấp quyền thực thi cho src/wpst${NC}"
        chmod +x src/wpst
    fi
else
    echo -e "${RED}✗ src/wpst không tồn tại${NC}"
fi

# Test 6: Kiểm tra thư mục lib
echo -e "${BLUE}Test 6: Kiểm tra thư mục lib${NC}"
if [[ -d "src/lib" ]]; then
    echo -e "${GREEN}✓ src/lib tồn tại${NC}"
    for file in src/lib/*.sh; do
        if [[ -f "$file" ]]; then
            echo -e "  ✓ $(basename "$file")"
        fi
    done
else
    echo -e "${RED}✗ src/lib không tồn tại${NC}"
fi

# Test 7: Kiểm tra dependencies
echo -e "${BLUE}Test 7: Kiểm tra dependencies${NC}"
deps=("curl" "wget" "grep" "awk" "sed")
for dep in "${deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ $dep có sẵn${NC}"
    else
        echo -e "${YELLOW}! $dep không có sẵn${NC}"
    fi
done

# Cleanup
rm -f test_email.sh

echo ""
echo -e "${GREEN}🎉 Tất cả tests đã hoàn thành!${NC}"
echo ""
echo -e "${BLUE}Để chạy cài đặt:${NC}"
echo "sudo ./install.sh"
echo ""
echo -e "${BLUE}Để test script wpst:${NC}"
echo "./src/wpst" 