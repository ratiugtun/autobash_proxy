#!/bin/bash

#############################################
# WSL2 Ubuntu Proxy Auto-Configuration Script
# For Ubuntu 24 on Windows 11 25H2 WSL2
# Network Mode: Mirrored
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration files
APT_PROXY_CONF="/etc/apt/apt.conf.d/95proxy"
ENV_FILE="/etc/environment"
PROFILE_SCRIPT="/etc/profile.d/proxy.sh"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get the first IPv4 address from hostname -I
get_ip_address() {
    local ip_list=$(hostname -I)
    # Extract the first IPv4 address (not IPv6)
    local ipv4=$(echo "$ip_list" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n 1)
    echo "$ipv4"
}

# Function to check if IP starts with 172.17
should_use_proxy() {
    local ip=$1
    if [[ "$ip" =~ ^172\.17\. ]]; then
        return 0  # true, should use proxy
    else
        return 1  # false, should not use proxy
    fi
}

# Function to remove proxy configuration
remove_proxy() {
    print_info "Removing proxy configuration..."

    # Remove APT proxy configuration
    if [ -f "$APT_PROXY_CONF" ]; then
        sudo rm -f "$APT_PROXY_CONF"
        print_success "Removed APT proxy configuration"
    fi

    # Remove profile script
    if [ -f "$PROFILE_SCRIPT" ]; then
        sudo rm -f "$PROFILE_SCRIPT"
        print_success "Removed profile proxy script"
    fi

    # Unset current session proxy variables
    unset http_proxy https_proxy ftp_proxy no_proxy
    unset HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY

    print_success "Proxy configuration removed. Please restart your terminal for full effect."
}

# Function to configure proxy
configure_proxy() {
    local proxy_host=$1
    local proxy_port=$2
    local proxy_user=$3
    local proxy_pass=$4

    # Build proxy URL
    local proxy_url
    if [ -n "$proxy_user" ] && [ -n "$proxy_pass" ]; then
        # URL encode username and password
        proxy_user_encoded=$(echo -n "$proxy_user" | jq -sRr @uri)
        proxy_pass_encoded=$(echo -n "$proxy_pass" | jq -sRr @uri)
        proxy_url="${proxy_user_encoded}:${proxy_pass_encoded}@${proxy_host}:${proxy_port}"
    else
        proxy_url="${proxy_host}:${proxy_port}"
    fi

    print_info "Configuring proxy settings..."

    # Configure APT proxy
    print_info "Configuring APT proxy..."
    sudo tee "$APT_PROXY_CONF" > /dev/null <<EOF
Acquire::http::Proxy "http://${proxy_url}";
Acquire::https::Proxy "http://${proxy_url}";
Acquire::ftp::Proxy "ftp://${proxy_url}";
EOF

    print_success "APT proxy configured at $APT_PROXY_CONF"

    # Configure system-wide proxy via profile.d
    print_info "Configuring system-wide proxy..."
    sudo tee "$PROFILE_SCRIPT" > /dev/null <<EOF
# Auto-generated proxy configuration
export http_proxy="http://${proxy_url}"
export https_proxy="http://${proxy_url}"
export ftp_proxy="ftp://${proxy_url}"
export no_proxy="localhost,127.0.0.1,::1"

export HTTP_PROXY="\${http_proxy}"
export HTTPS_PROXY="\${https_proxy}"
export FTP_PROXY="\${ftp_proxy}"
export NO_PROXY="\${no_proxy}"
EOF

    sudo chmod +x "$PROFILE_SCRIPT"
    print_success "System-wide proxy configured at $PROFILE_SCRIPT"

    # Set for current session
    export http_proxy="http://${proxy_url}"
    export https_proxy="http://${proxy_url}"
    export ftp_proxy="ftp://${proxy_url}"
    export no_proxy="localhost,127.0.0.1,::1"
    export HTTP_PROXY="${http_proxy}"
    export HTTPS_PROXY="${https_proxy}"
    export FTP_PROXY="${ftp_proxy}"
    export NO_PROXY="${no_proxy}"

    print_success "Proxy configured for current session"
    print_warning "For full effect in all applications, please restart your terminal or run: source $PROFILE_SCRIPT"
}

# Function to check if jq is available (for URL encoding)
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Installing for URL encoding..."
        if [ "$EUID" -ne 0 ]; then
            print_info "Attempting to install jq with sudo..."
            sudo apt-get update -qq && sudo apt-get install -y jq
        else
            apt-get update -qq && apt-get install -y jq
        fi
    fi
}

# Main script
main() {
    echo ""
    echo "================================================"
    echo "   WSL2 Ubuntu Proxy Auto-Configuration"
    echo "================================================"
    echo ""

    # Get current IP address
    print_info "Detecting IP address..."
    CURRENT_IP=$(get_ip_address)

    if [ -z "$CURRENT_IP" ]; then
        print_error "Could not detect IP address"
        exit 1
    fi

    print_success "Detected IP address: $CURRENT_IP"

    # Check if proxy should be configured
    if should_use_proxy "$CURRENT_IP"; then
        print_success "IP starts with 172.17 - Proxy configuration required"
        echo ""

        # Check dependencies
        check_dependencies

        # Prompt for proxy details
        read -p "Enter proxy host (e.g., proxy.company.com or IP): " PROXY_HOST

        if [ -z "$PROXY_HOST" ]; then
            print_error "Proxy host is required"
            exit 1
        fi

        read -p "Enter proxy port [default: 8080]: " PROXY_PORT
        PROXY_PORT=${PROXY_PORT:-8080}

        echo ""
        read -p "Does the proxy require authentication? (y/n) [default: y]: " REQUIRE_AUTH
        REQUIRE_AUTH=${REQUIRE_AUTH:-y}

        PROXY_USER=""
        PROXY_PASS=""

        if [[ "$REQUIRE_AUTH" =~ ^[Yy]$ ]]; then
            read -p "Enter proxy username: " PROXY_USER
            read -sp "Enter proxy password: " PROXY_PASS
            echo ""

            if [ -z "$PROXY_USER" ] || [ -z "$PROXY_PASS" ]; then
                print_error "Username and password are required for authentication"
                exit 1
            fi
        fi

        echo ""
        configure_proxy "$PROXY_HOST" "$PROXY_PORT" "$PROXY_USER" "$PROXY_PASS"

        echo ""
        print_success "Proxy configuration completed!"
        echo ""
        echo "To verify, run:"
        echo "  echo \$http_proxy"
        echo "  sudo apt-get update"

    else
        print_info "IP does not start with 172.17 - No proxy needed"

        # Check if proxy is currently configured
        if [ -f "$APT_PROXY_CONF" ] || [ -f "$PROFILE_SCRIPT" ]; then
            echo ""
            read -p "Existing proxy configuration found. Remove it? (y/n) [default: y]: " REMOVE_PROXY
            REMOVE_PROXY=${REMOVE_PROXY:-y}

            if [[ "$REMOVE_PROXY" =~ ^[Yy]$ ]]; then
                remove_proxy
            else
                print_info "Keeping existing proxy configuration"
            fi
        else
            print_success "No proxy configuration needed and none found"
        fi
    fi

    echo ""
    echo "================================================"
    echo "   Configuration Complete"
    echo "================================================"
    echo ""
}

# Run main function
main
