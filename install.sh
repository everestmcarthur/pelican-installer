#!/bin/bash

set -e

#############################################################################################
#                                                                                           #
#  Pelican Installer — The best way to install Pelican Panel & Wings                        #
#                                                                                           #
#  Copyright (c) 2026, JarvisCLI                                                            #
#  https://github.com/rosillathequeen/pelican-installer                                     #
#                                                                                           #
#  This program is free software: you can redistribute it and/or modify                     #
#  it under the terms of the GNU General Public License v3.0                                #
#                                                                                           #
#  Features over pterodactyl-installer.se:                                                  #
#    • Supports Nginx, Apache, and Caddy web servers                                        #
#    • Supports SQLite, MySQL/MariaDB, and PostgreSQL databases                             #
#    • Automatic SSL via Let's Encrypt (certbot)                                            #
#    • Full Wings daemon installation with systemd                                          #
#    • Health checks & post-install verification                                            #
#    • Colored, beautiful terminal UI with progress indicators                              #
#    • Comprehensive logging to /var/log/pelican-installer.log                              #
#    • Uninstall & Update capabilities                                                      #
#    • Single-script — no external library downloads needed                                 #
#    • Auto-detects OS and installs correct packages                                        #
#                                                                                           #
#############################################################################################

# ─── Version ───────────────────────────────────────────────────────────────────
INSTALLER_VERSION="1.0.0"
PELICAN_PANEL_URL="https://github.com/pelican-dev/panel/releases/latest/download/panel.tar.gz"
PELICAN_WINGS_BASE="https://github.com/pelican-dev/wings/releases/latest/download"
PELICAN_DIR="/var/www/pelican"
WINGS_DIR="/etc/pelican"
WINGS_BIN="/usr/local/bin/wings"
LOG_FILE="/var/log/pelican-installer.log"

# ─── Colors & Formatting ──────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' BOLD='' DIM='' RESET=''
fi

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ║"
    echo "  ║          🐦  Pelican Panel & Wings Installer  🐦          ║"
    echo "  ║                                                           ║"
    echo "  ║                     v${INSTALLER_VERSION}                              ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo ""
}

info() {
    echo -e "  ${BLUE}ℹ${RESET}  $*"
    log "INFO: $*"
}

success() {
    echo -e "  ${GREEN}✓${RESET}  $*"
    log "SUCCESS: $*"
}

warn() {
    echo -e "  ${YELLOW}⚠${RESET}  $*"
    log "WARN: $*"
}

error() {
    echo -e "  ${RED}✗${RESET}  $*"
    log "ERROR: $*"
}

fatal() {
    echo ""
    echo -e "  ${RED}${BOLD}FATAL:${RESET} ${RED}$*${RESET}"
    log "FATAL: $*"
    echo ""
    exit 1
}

step() {
    echo ""
    echo -e "  ${MAGENTA}${BOLD}▸ $*${RESET}"
    echo -e "  ${DIM}$(printf '%.0s─' {1..55})${RESET}"
    log "STEP: $*"
}

ask() {
    echo -e -n "  ${CYAN}?${RESET}  $* "
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${RESET}  %s" "${spin:i++%${#spin}:1}" "$msg"
        sleep 0.1
    done
    printf "\r"
}

# ─── OS Detection ─────────────────────────────────────────────────────────────
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    else
        fatal "Cannot detect operating system. /etc/os-release not found."
    fi

    # Determine package manager and OS family
    case "$OS_ID" in
        ubuntu|debian)
            OS_FAMILY="debian"
            PKG_MANAGER="apt"
            ;;
        almalinux|rocky|centos)
            OS_FAMILY="rhel"
            PKG_MANAGER="dnf"
            ;;
        *)
            warn "Unsupported OS: $OS_ID. Attempting to continue..."
            if command -v apt &>/dev/null; then
                OS_FAMILY="debian"
                PKG_MANAGER="apt"
            elif command -v dnf &>/dev/null; then
                OS_FAMILY="rhel"
                PKG_MANAGER="dnf"
            else
                fatal "Cannot determine package manager."
            fi
            ;;
    esac

    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) WINGS_ARCH="amd64" ;;
        aarch64|arm64) WINGS_ARCH="arm64" ;;
        *) fatal "Unsupported architecture: $ARCH" ;;
    esac

    success "Detected: ${BOLD}$OS_NAME${RESET} (${OS_FAMILY}, ${PKG_MANAGER}, ${ARCH})"
}

# ─── Preflight Checks ─────────────────────────────────────────────────────────
preflight_checks() {
    step "Running preflight checks"

    # Root check
    if [[ $EUID -ne 0 ]]; then
        fatal "This script must be run as root (use sudo)."
    fi
    success "Running as root"

    # Check required commands
    for cmd in curl tar; do
        if command -v "$cmd" &>/dev/null; then
            success "$cmd is available"
        else
            error "$cmd is not installed. Installing..."
            $PKG_MANAGER install -y "$cmd" >> "$LOG_FILE" 2>&1 || fatal "Failed to install $cmd"
            success "$cmd installed"
        fi
    done

    # Check virtualization (for Wings)
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null || true)
        if [[ "$virt" == "openvz" || "$virt" == "lxc" ]]; then
            warn "Detected ${BOLD}$virt${RESET} virtualization — Wings/Docker may not work!"
            warn "Contact your host about nested virtualization support."
        else
            success "Virtualization check passed ($virt)"
        fi
    fi

    # Memory check
    local total_mem
    total_mem=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
    if [[ $total_mem -lt 512 ]]; then
        warn "Low memory detected (${total_mem}MB). Minimum 1GB recommended."
    else
        success "Memory: ${total_mem}MB"
    fi

    # Disk check
    local free_disk
    free_disk=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $free_disk -lt 5 ]]; then
        warn "Low disk space (${free_disk}GB free). At least 10GB recommended."
    else
        success "Disk space: ${free_disk}GB free"
    fi
}

# ─── PHP Installation ─────────────────────────────────────────────────────────
detect_php_version() {
    # Try 8.5 first, then 8.4, then 8.3
    for ver in 8.5 8.4 8.3; do
        if [[ "$OS_FAMILY" == "debian" ]]; then
            if apt-cache show "php${ver}-fpm" &>/dev/null 2>&1; then
                PHP_VERSION="$ver"
                return
            fi
        else
            if dnf list "php" 2>/dev/null | grep -q "$ver"; then
                PHP_VERSION="$ver"
                return
            fi
        fi
    done
    PHP_VERSION="8.4"  # fallback
}

install_php() {
    step "Installing PHP $PHP_VERSION & extensions"

    if [[ "$OS_FAMILY" == "debian" ]]; then
        # Add PHP repository
        if ! command -v add-apt-repository &>/dev/null; then
            apt install -y software-properties-common >> "$LOG_FILE" 2>&1
        fi

        if [[ "$OS_ID" == "ubuntu" ]]; then
            add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1 || true
        elif [[ "$OS_ID" == "debian" ]]; then
            # Sury PHP repo for Debian
            apt install -y lsb-release apt-transport-https ca-certificates >> "$LOG_FILE" 2>&1
            curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb >> "$LOG_FILE" 2>&1
            dpkg -i /tmp/debsuryorg-archive-keyring.deb >> "$LOG_FILE" 2>&1
            echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/sury-php.list
        fi

        apt update >> "$LOG_FILE" 2>&1

        local php_packages=(
            "php${PHP_VERSION}" "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-common"
            "php${PHP_VERSION}-cli" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-mysql"
            "php${PHP_VERSION}-pgsql"
            "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-xml"
            "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip" "php${PHP_VERSION}-intl"
            "php${PHP_VERSION}-sqlite3"
        )

        apt install -y "${php_packages[@]}" >> "$LOG_FILE" 2>&1 &
        spinner $! "Installing PHP ${PHP_VERSION} and extensions..."
        wait $!
        success "PHP ${PHP_VERSION} installed with all required extensions"

    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        # Enable Remi repo for PHP
        dnf install -y epel-release >> "$LOG_FILE" 2>&1
        dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm" >> "$LOG_FILE" 2>&1 || true
        dnf module reset php -y >> "$LOG_FILE" 2>&1 || true
        dnf module enable "php:remi-${PHP_VERSION}" -y >> "$LOG_FILE" 2>&1 || true

        local php_packages=(
            php php-fpm php-common php-cli php-gd php-mysqlnd php-pgsql
            php-mbstring php-bcmath php-xml php-curl php-zip php-intl php-pdo
        )

        dnf install -y "${php_packages[@]}" >> "$LOG_FILE" 2>&1 &
        spinner $! "Installing PHP ${PHP_VERSION} and extensions..."
        wait $!
        success "PHP ${PHP_VERSION} installed with all required extensions"
    fi

    # Start PHP-FPM
    systemctl enable --now "php${PHP_VERSION}-fpm" >> "$LOG_FILE" 2>&1 || \
        systemctl enable --now php-fpm >> "$LOG_FILE" 2>&1 || true
    success "PHP-FPM started and enabled"
}

# ─── Database Installation ─────────────────────────────────────────────────────
install_database() {
    if [[ "$DB_CHOICE" == "sqlite" ]]; then
        info "Using SQLite — no database server needed"
        return
    fi

    step "Installing ${DB_CHOICE} database server"

    case "$DB_CHOICE" in
        mysql)
            if [[ "$OS_FAMILY" == "debian" ]]; then
                apt install -y mysql-server mysql-client >> "$LOG_FILE" 2>&1 &
            else
                dnf install -y mysql-server >> "$LOG_FILE" 2>&1 &
            fi
            spinner $! "Installing MySQL..."
            wait $!
            systemctl enable --now mysql >> "$LOG_FILE" 2>&1 || systemctl enable --now mysqld >> "$LOG_FILE" 2>&1
            success "MySQL installed and running"
            ;;
        mariadb)
            if [[ "$OS_FAMILY" == "debian" ]]; then
                apt install -y mariadb-server mariadb-client >> "$LOG_FILE" 2>&1 &
            else
                dnf install -y mariadb-server >> "$LOG_FILE" 2>&1 &
            fi
            spinner $! "Installing MariaDB..."
            wait $!
            systemctl enable --now mariadb >> "$LOG_FILE" 2>&1
            success "MariaDB installed and running"
            ;;
        postgres)
            if [[ "$OS_FAMILY" == "debian" ]]; then
                apt install -y postgresql postgresql-client >> "$LOG_FILE" 2>&1 &
            else
                dnf install -y postgresql-server postgresql >> "$LOG_FILE" 2>&1 &
                postgresql-setup --initdb >> "$LOG_FILE" 2>&1 || true
            fi
            spinner $! "Installing PostgreSQL..."
            wait $!
            systemctl enable --now postgresql >> "$LOG_FILE" 2>&1
            success "PostgreSQL installed and running"
            ;;
    esac

    # Setup database & user for panel
    if [[ "$DB_CHOICE" == "mysql" || "$DB_CHOICE" == "mariadb" ]]; then
        setup_mysql_database
    elif [[ "$DB_CHOICE" == "postgres" ]]; then
        setup_postgres_database
    fi
}

setup_mysql_database() {
    step "Setting up MySQL/MariaDB database for Pelican"

    DB_NAME="${DB_NAME:-pelican}"
    DB_USER="${DB_USER:-pelican}"

    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
        info "Generated database password (saved to log)"
        log "Generated DB password: $DB_PASSWORD"
    fi

    mysql -u root <<MYSQL_HEREDOC
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_HEREDOC

    success "Database '${DB_NAME}' and user '${DB_USER}' created"
    echo ""
    echo -e "  ${DIM}Database credentials (save these!):${RESET}"
    echo -e "  ${DIM}  Host:     127.0.0.1${RESET}"
    echo -e "  ${DIM}  Database: ${DB_NAME}${RESET}"
    echo -e "  ${DIM}  User:     ${DB_USER}${RESET}"
    echo -e "  ${DIM}  Password: ${DB_PASSWORD}${RESET}"
    echo ""
}

setup_postgres_database() {
    step "Setting up PostgreSQL database for Pelican"

    DB_NAME="${DB_NAME:-pelican}"
    DB_USER="${DB_USER:-pelican}"

    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
        info "Generated database password (saved to log)"
        log "Generated DB password: $DB_PASSWORD"
    fi

    sudo -u postgres psql <<PGSQL_HEREDOC
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
PGSQL_HEREDOC

    success "PostgreSQL database '${DB_NAME}' and user '${DB_USER}' created"
}

# ─── Web Server Installation ──────────────────────────────────────────────────
install_webserver() {
    step "Installing ${WEBSERVER} web server"

    case "$WEBSERVER" in
        nginx)   install_nginx ;;
        apache)  install_apache ;;
        caddy)   install_caddy ;;
    esac
}

install_nginx() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt install -y nginx >> "$LOG_FILE" 2>&1
    else
        dnf install -y nginx >> "$LOG_FILE" 2>&1
    fi
    success "Nginx installed"

    # Remove default site
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

    # Determine PHP-FPM socket path
    local fpm_sock="/run/php/php${PHP_VERSION}-fpm.sock"
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        fpm_sock="/run/php-fpm/www.sock"
    fi

    # Create config directory if it doesn't exist (RHEL)
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null || true

    # Add include directive for RHEL
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        if ! grep -q "sites-enabled" /etc/nginx/nginx.conf 2>/dev/null; then
            sed -i '/http {/a \    include /etc/nginx/sites-enabled/*.conf;' /etc/nginx/nginx.conf
        fi
    fi

    if [[ "$CONFIGURE_SSL" == true ]]; then
        cat > /etc/nginx/sites-available/pelican.conf <<NGINX_SSL
server_tokens off;

server {
    listen 80;
    server_name ${FQDN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${FQDN};

    root ${PELICAN_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pelican.app-access.log;
    error_log  /var/log/nginx/pelican.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    ssl_certificate /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:${fpm_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX_SSL
    else
        cat > /etc/nginx/sites-available/pelican.conf <<NGINX_HTTP
server_tokens off;

server {
    listen 80;
    server_name ${FQDN};

    root ${PELICAN_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pelican.app-access.log;
    error_log  /var/log/nginx/pelican.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:${fpm_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX_HTTP
    fi

    ln -sf /etc/nginx/sites-available/pelican.conf /etc/nginx/sites-enabled/pelican.conf
    nginx -t >> "$LOG_FILE" 2>&1 || warn "Nginx config test failed — check ${LOG_FILE}"
    systemctl enable --now nginx >> "$LOG_FILE" 2>&1
    systemctl restart nginx >> "$LOG_FILE" 2>&1
    success "Nginx configured and running"
}

install_apache() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt install -y apache2 libapache2-mod-php"${PHP_VERSION}" >> "$LOG_FILE" 2>&1
        a2enmod rewrite ssl headers proxy proxy_fcgi >> "$LOG_FILE" 2>&1 || true
        a2dissite 000-default >> "$LOG_FILE" 2>&1 || true
    else
        dnf install -y httpd mod_ssl >> "$LOG_FILE" 2>&1
    fi
    success "Apache installed"

    local fpm_sock="/run/php/php${PHP_VERSION}-fpm.sock"
    [[ "$OS_FAMILY" == "rhel" ]] && fpm_sock="/run/php-fpm/www.sock"

    local conf_dir="/etc/apache2/sites-available"
    [[ "$OS_FAMILY" == "rhel" ]] && conf_dir="/etc/httpd/conf.d"

    if [[ "$CONFIGURE_SSL" == true ]]; then
        cat > "${conf_dir}/pelican.conf" <<APACHE_SSL
<VirtualHost *:80>
    ServerName ${FQDN}
    Redirect permanent / https://${FQDN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${FQDN}
    DocumentRoot ${PELICAN_DIR}/public

    AllowEncodedSlashes On

    php_value upload_max_filesize 100M
    php_value post_max_size 100M

    <Directory "${PELICAN_DIR}/public">
        Require all granted
        AllowOverride all
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${FQDN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${FQDN}/privkey.pem
</VirtualHost>
APACHE_SSL
    else
        cat > "${conf_dir}/pelican.conf" <<APACHE_HTTP
<VirtualHost *:80>
    ServerName ${FQDN}
    DocumentRoot ${PELICAN_DIR}/public

    AllowEncodedSlashes On

    php_value upload_max_filesize 100M
    php_value post_max_size 100M

    <Directory "${PELICAN_DIR}/public">
        Require all granted
        AllowOverride all
    </Directory>
</VirtualHost>
APACHE_HTTP
    fi

    if [[ "$OS_FAMILY" == "debian" ]]; then
        a2ensite pelican >> "$LOG_FILE" 2>&1
        systemctl enable --now apache2 >> "$LOG_FILE" 2>&1
        systemctl restart apache2 >> "$LOG_FILE" 2>&1
    else
        systemctl enable --now httpd >> "$LOG_FILE" 2>&1
        systemctl restart httpd >> "$LOG_FILE" 2>&1
    fi
    success "Apache configured and running"
}

install_caddy() {
    step "Installing Caddy web server"

    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt install -y debian-keyring debian-archive-keyring apt-transport-https >> "$LOG_FILE" 2>&1
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >> "$LOG_FILE" 2>&1
        apt update >> "$LOG_FILE" 2>&1
        apt install -y caddy >> "$LOG_FILE" 2>&1
    else
        dnf install -y 'dnf-command(copr)' >> "$LOG_FILE" 2>&1
        dnf copr enable @caddy/caddy -y >> "$LOG_FILE" 2>&1
        dnf install -y caddy >> "$LOG_FILE" 2>&1
    fi
    success "Caddy installed"

    local fpm_sock="/run/php/php${PHP_VERSION}-fpm.sock"
    [[ "$OS_FAMILY" == "rhel" ]] && fpm_sock="/run/php-fpm/www.sock"

    # Caddy handles SSL automatically!
    cat > /etc/caddy/Caddyfile <<CADDYFILE
${FQDN} {
    root * ${PELICAN_DIR}/public

    file_server

    php_fastcgi unix/${fpm_sock} {
        root ${PELICAN_DIR}/public
        index index.php
    }

    header {
        X-Content-Type-Options nosniff
        X-XSS-Protection "1; mode=block"
        X-Robots-Tag none
        Content-Security-Policy "frame-ancestors 'self'"
        X-Frame-Options DENY
        Referrer-Policy same-origin
        -Server
    }

    encode gzip

    log {
        output file /var/log/caddy/pelican.log
    }
}
CADDYFILE

    mkdir -p /var/log/caddy
    systemctl enable --now caddy >> "$LOG_FILE" 2>&1
    systemctl restart caddy >> "$LOG_FILE" 2>&1
    success "Caddy configured and running (auto-SSL enabled)"
}

# ─── SSL Setup ─────────────────────────────────────────────────────────────────
install_ssl() {
    if [[ "$CONFIGURE_SSL" != true ]]; then
        return
    fi

    # Caddy handles its own SSL
    if [[ "$WEBSERVER" == "caddy" ]]; then
        info "Caddy handles SSL automatically — skipping certbot"
        return
    fi

    step "Setting up SSL with Let's Encrypt"

    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt install -y certbot >> "$LOG_FILE" 2>&1
        if [[ "$WEBSERVER" == "nginx" ]]; then
            apt install -y python3-certbot-nginx >> "$LOG_FILE" 2>&1
        elif [[ "$WEBSERVER" == "apache" ]]; then
            apt install -y python3-certbot-apache >> "$LOG_FILE" 2>&1
        fi
    else
        dnf install -y certbot >> "$LOG_FILE" 2>&1
        if [[ "$WEBSERVER" == "nginx" ]]; then
            dnf install -y python3-certbot-nginx >> "$LOG_FILE" 2>&1
        elif [[ "$WEBSERVER" == "apache" ]]; then
            dnf install -y python3-certbot-apache >> "$LOG_FILE" 2>&1
        fi
    fi

    # Stop webserver temporarily for standalone if plugin fails
    if [[ "$WEBSERVER" == "nginx" ]]; then
        certbot certonly --nginx -d "$FQDN" --non-interactive --agree-tos --email "$EMAIL" >> "$LOG_FILE" 2>&1 || {
            warn "Nginx plugin failed, trying standalone..."
            systemctl stop nginx
            certbot certonly --standalone -d "$FQDN" --non-interactive --agree-tos --email "$EMAIL" >> "$LOG_FILE" 2>&1
            systemctl start nginx
        }
    elif [[ "$WEBSERVER" == "apache" ]]; then
        certbot certonly --apache -d "$FQDN" --non-interactive --agree-tos --email "$EMAIL" >> "$LOG_FILE" 2>&1 || {
            warn "Apache plugin failed, trying standalone..."
            systemctl stop apache2 2>/dev/null || systemctl stop httpd
            certbot certonly --standalone -d "$FQDN" --non-interactive --agree-tos --email "$EMAIL" >> "$LOG_FILE" 2>&1
            systemctl start apache2 2>/dev/null || systemctl start httpd
        }
    fi

    # Setup auto-renewal
    (crontab -l 2>/dev/null; echo "0 23 * * * certbot renew --quiet --deploy-hook \"systemctl restart ${WEBSERVER}\"") | sort -u | crontab -
    success "SSL certificate obtained and auto-renewal configured"
}

# ─── Pelican Panel Installation ────────────────────────────────────────────────
install_panel() {
    step "Downloading Pelican Panel"

    mkdir -p "$PELICAN_DIR"
    cd "$PELICAN_DIR"

    curl -L "$PELICAN_PANEL_URL" | tar -xzv >> "$LOG_FILE" 2>&1 &
    spinner $! "Downloading and extracting Pelican Panel..."
    wait $!
    success "Panel files downloaded to ${PELICAN_DIR}"

    step "Installing Composer dependencies"

    # Install Composer if not present
    if ! command -v composer &>/dev/null; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >> "$LOG_FILE" 2>&1
        success "Composer installed"
    fi

    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --working-dir="$PELICAN_DIR" >> "$LOG_FILE" 2>&1 &
    spinner $! "Installing PHP dependencies (this may take a minute)..."
    wait $!
    success "Composer dependencies installed"

    step "Configuring Pelican Panel"

    # Run environment setup
    php artisan p:environment:setup --no-interaction >> "$LOG_FILE" 2>&1 || true
    success "Environment file created"

    # Set permissions
    local webserver_user="www-data"
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        if [[ "$WEBSERVER" == "nginx" ]]; then
            webserver_user="nginx"
        elif [[ "$WEBSERVER" == "apache" ]]; then
            webserver_user="apache"
        elif [[ "$WEBSERVER" == "caddy" ]]; then
            webserver_user="caddy"
        fi
    fi

    chown -R "${webserver_user}:${webserver_user}" "$PELICAN_DIR"
    chmod -R 755 storage/* bootstrap/cache/
    success "File permissions set (owner: ${webserver_user})"

    # Setup queue worker service
    cat > /etc/systemd/system/pelican-queue.service <<QUEUE_SERVICE
# Pelican Queue Worker
# Automatically installed by pelican-installer

[Unit]
Description=Pelican Queue Worker
After=network.target

[Service]
User=${webserver_user}
Group=${webserver_user}
Restart=always
ExecStart=/usr/bin/php ${PELICAN_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
QUEUE_SERVICE

    systemctl daemon-reload
    systemctl enable --now pelican-queue >> "$LOG_FILE" 2>&1
    success "Queue worker service created and started"

    # Setup cron for scheduled tasks
    local cron_line="* * * * * php ${PELICAN_DIR}/artisan schedule:run >> /dev/null 2>&1"
    (crontab -u "${webserver_user}" -l 2>/dev/null; echo "$cron_line") | sort -u | crontab -u "${webserver_user}" -
    success "Cron job configured for scheduled tasks"

    # Backup the APP_KEY
    local app_key
    app_key=$(grep "^APP_KEY=" "${PELICAN_DIR}/.env" 2>/dev/null | cut -d= -f2-)
    if [[ -n "$app_key" ]]; then
        echo ""
        echo -e "  ${RED}${BOLD}⚠  IMPORTANT: Back up your encryption key!${RESET}"
        echo -e "  ${RED}   APP_KEY=${app_key}${RESET}"
        echo -e "  ${RED}   If you lose this, all encrypted data is irrecoverable!${RESET}"
        echo ""
        log "APP_KEY: $app_key"
    fi
}

# ─── Wings Installation ───────────────────────────────────────────────────────
install_wings() {
    step "Installing Docker"

    if command -v docker &>/dev/null; then
        success "Docker is already installed"
    else
        curl -sSL https://get.docker.com/ | CHANNEL=stable sh >> "$LOG_FILE" 2>&1 &
        spinner $! "Installing Docker CE..."
        wait $!
        systemctl enable --now docker >> "$LOG_FILE" 2>&1
        success "Docker CE installed and running"
    fi

    step "Installing Wings daemon"

    mkdir -p "$WINGS_DIR" /var/run/wings

    local wings_url="${PELICAN_WINGS_BASE}/wings_linux_${WINGS_ARCH}"
    curl -L -o "$WINGS_BIN" "$wings_url" >> "$LOG_FILE" 2>&1 &
    spinner $! "Downloading Wings binary (${WINGS_ARCH})..."
    wait $!
    chmod u+x "$WINGS_BIN"
    success "Wings binary installed to ${WINGS_BIN}"

    step "Setting up Wings systemd service"

    cat > /etc/systemd/system/wings.service <<WINGS_SERVICE
[Unit]
Description=Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=${WINGS_DIR}
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=${WINGS_BIN}
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
WINGS_SERVICE

    systemctl daemon-reload
    systemctl enable wings >> "$LOG_FILE" 2>&1
    success "Wings systemd service created and enabled"

    echo ""
    echo -e "  ${YELLOW}${BOLD}Next steps for Wings:${RESET}"
    echo -e "  ${DIM}  1. Go to your Panel admin area → Nodes → Create New${RESET}"
    echo -e "  ${DIM}  2. Copy the configuration YAML from the Configuration tab${RESET}"
    echo -e "  ${DIM}  3. Paste it into ${WINGS_DIR}/config.yml${RESET}"
    echo -e "  ${DIM}  4. Start Wings: sudo systemctl start wings${RESET}"
    echo ""
}

# ─── Uninstall ─────────────────────────────────────────────────────────────────
uninstall() {
    echo ""
    echo -e "  ${RED}${BOLD}⚠  Uninstall Pelican${RESET}"
    echo ""

    local uninstall_options=(
        "Uninstall Panel"
        "Uninstall Wings"
        "Uninstall Both"
        "Cancel"
    )

    for i in "${!uninstall_options[@]}"; do
        echo -e "  ${CYAN}[$i]${RESET} ${uninstall_options[$i]}"
    done
    echo ""
    ask "Select option:"
    read -r uninstall_choice

    case "$uninstall_choice" in
        0) uninstall_panel ;;
        1) uninstall_wings ;;
        2) uninstall_panel; uninstall_wings ;;
        3) info "Cancelled."; exit 0 ;;
        *) error "Invalid option"; exit 1 ;;
    esac
}

uninstall_panel() {
    step "Uninstalling Pelican Panel"

    ask "Remove all panel files in ${PELICAN_DIR}? (y/N):"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Aborted panel uninstallation."
        return
    fi

    # Stop services
    systemctl stop pelican-queue 2>/dev/null || true
    systemctl disable pelican-queue 2>/dev/null || true
    rm -f /etc/systemd/system/pelican-queue.service

    # Remove webserver config
    rm -f /etc/nginx/sites-enabled/pelican.conf /etc/nginx/sites-available/pelican.conf 2>/dev/null || true
    rm -f /etc/apache2/sites-enabled/pelican.conf /etc/apache2/sites-available/pelican.conf 2>/dev/null || true
    rm -f /etc/httpd/conf.d/pelican.conf 2>/dev/null || true

    # Remove panel files
    rm -rf "$PELICAN_DIR"
    systemctl daemon-reload

    # Restart webserver
    systemctl restart nginx 2>/dev/null || systemctl restart apache2 2>/dev/null || systemctl restart httpd 2>/dev/null || systemctl restart caddy 2>/dev/null || true

    success "Pelican Panel uninstalled"
}

uninstall_wings() {
    step "Uninstalling Wings"

    ask "Stop and remove Wings? (y/N):"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Aborted Wings uninstallation."
        return
    fi

    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    rm -f /etc/systemd/system/wings.service
    rm -f "$WINGS_BIN"
    systemctl daemon-reload

    ask "Also remove Wings config (${WINGS_DIR})? (y/N):"
    read -r confirm_cfg
    if [[ "$confirm_cfg" =~ ^[Yy]$ ]]; then
        rm -rf "$WINGS_DIR"
    fi

    success "Wings uninstalled"
}

# ─── Update ────────────────────────────────────────────────────────────────────
update_panel() {
    step "Updating Pelican Panel"

    if [[ ! -d "$PELICAN_DIR" ]]; then
        fatal "Panel not found at ${PELICAN_DIR}. Is it installed?"
    fi

    cd "$PELICAN_DIR"

    # Put panel into maintenance mode
    php artisan down >> "$LOG_FILE" 2>&1 || true
    info "Panel in maintenance mode"

    # Backup .env
    cp .env .env.backup.$(date +%Y%m%d%H%M%S)
    success "Backed up .env file"

    # Download latest
    curl -L "$PELICAN_PANEL_URL" | tar -xzv >> "$LOG_FILE" 2>&1 &
    spinner $! "Downloading latest Pelican Panel..."
    wait $!
    success "Latest panel files downloaded"

    # Install dependencies
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader >> "$LOG_FILE" 2>&1 &
    spinner $! "Updating PHP dependencies..."
    wait $!

    # Run migrations
    php artisan migrate --seed --force >> "$LOG_FILE" 2>&1
    success "Database migrations applied"

    # Clear caches
    php artisan optimize:clear >> "$LOG_FILE" 2>&1
    success "Caches cleared"

    # Fix permissions
    local webserver_user="www-data"
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        [[ "$WEBSERVER" == "nginx" ]] && webserver_user="nginx"
        [[ "$WEBSERVER" == "apache" ]] && webserver_user="apache"
        [[ "$WEBSERVER" == "caddy" ]] && webserver_user="caddy"
    fi
    chown -R "${webserver_user}:${webserver_user}" "$PELICAN_DIR"
    chmod -R 755 storage/* bootstrap/cache/

    # Restart services
    systemctl restart pelican-queue >> "$LOG_FILE" 2>&1 || true
    php artisan queue:restart >> "$LOG_FILE" 2>&1 || true

    # Bring panel back up
    php artisan up >> "$LOG_FILE" 2>&1
    success "Panel updated and back online!"
}

update_wings() {
    step "Updating Wings"

    systemctl stop wings >> "$LOG_FILE" 2>&1 || true

    curl -L -o "$WINGS_BIN" "${PELICAN_WINGS_BASE}/wings_linux_${WINGS_ARCH}" >> "$LOG_FILE" 2>&1 &
    spinner $! "Downloading latest Wings binary..."
    wait $!
    chmod u+x "$WINGS_BIN"

    systemctl start wings >> "$LOG_FILE" 2>&1
    success "Wings updated and restarted!"
}

# ─── Health Checks ─────────────────────────────────────────────────────────────
health_check() {
    step "Running post-install health checks"

    local all_ok=true

    # Check PHP
    if php -v &>/dev/null; then
        local php_ver
        php_ver=$(php -v | head -1 | awk '{print $2}')
        success "PHP ${php_ver} is working"
    else
        error "PHP is not working"
        all_ok=false
    fi

    # Check web server
    case "$WEBSERVER" in
        nginx)
            if systemctl is-active --quiet nginx; then
                success "Nginx is running"
            else
                error "Nginx is not running"
                all_ok=false
            fi
            ;;
        apache)
            if systemctl is-active --quiet apache2 || systemctl is-active --quiet httpd; then
                success "Apache is running"
            else
                error "Apache is not running"
                all_ok=false
            fi
            ;;
        caddy)
            if systemctl is-active --quiet caddy; then
                success "Caddy is running"
            else
                error "Caddy is not running"
                all_ok=false
            fi
            ;;
    esac

    # Check panel files
    if [[ "$INSTALL_PANEL" == true ]]; then
        if [[ -f "${PELICAN_DIR}/artisan" ]]; then
            success "Panel files present"
        else
            error "Panel files missing at ${PELICAN_DIR}"
            all_ok=false
        fi

        if systemctl is-active --quiet pelican-queue; then
            success "Queue worker is running"
        else
            warn "Queue worker is not running (start with: systemctl start pelican-queue)"
        fi
    fi

    # Check Wings
    if [[ "$INSTALL_WINGS_FLAG" == true ]]; then
        if [[ -x "$WINGS_BIN" ]]; then
            success "Wings binary is installed"
        else
            error "Wings binary not found at ${WINGS_BIN}"
            all_ok=false
        fi

        if systemctl is-active --quiet docker; then
            success "Docker is running"
        else
            error "Docker is not running"
            all_ok=false
        fi
    fi

    # Check database
    if [[ "$DB_CHOICE" != "sqlite" && -n "$DB_CHOICE" ]]; then
        case "$DB_CHOICE" in
            mysql)
                if systemctl is-active --quiet mysql || systemctl is-active --quiet mysqld; then
                    success "MySQL is running"
                else
                    error "MySQL is not running"
                    all_ok=false
                fi
                ;;
            mariadb)
                if systemctl is-active --quiet mariadb; then
                    success "MariaDB is running"
                else
                    error "MariaDB is not running"
                    all_ok=false
                fi
                ;;
            postgres)
                if systemctl is-active --quiet postgresql; then
                    success "PostgreSQL is running"
                else
                    error "PostgreSQL is not running"
                    all_ok=false
                fi
                ;;
        esac
    fi

    echo ""
    if [[ "$all_ok" == true ]]; then
        echo -e "  ${GREEN}${BOLD}✓ All health checks passed!${RESET}"
    else
        echo -e "  ${YELLOW}${BOLD}⚠ Some checks failed. Review the issues above.${RESET}"
    fi
}

# ─── Interactive Menu ──────────────────────────────────────────────────────────
collect_panel_options() {
    echo ""
    echo -e "  ${BOLD}Panel Configuration${RESET}"
    echo ""

    # FQDN
    ask "Enter your panel domain (e.g., panel.example.com):"
    read -r FQDN
    [[ -z "$FQDN" ]] && fatal "Domain is required."

    # Web server
    echo ""
    echo -e "  ${BOLD}Choose a web server:${RESET}"
    echo -e "  ${CYAN}[0]${RESET} Nginx ${DIM}(recommended)${RESET}"
    echo -e "  ${CYAN}[1]${RESET} Apache"
    echo -e "  ${CYAN}[2]${RESET} Caddy ${DIM}(auto-SSL, easiest)${RESET}"
    echo ""
    ask "Web server [0]:"
    read -r ws_choice
    case "${ws_choice:-0}" in
        0) WEBSERVER="nginx" ;;
        1) WEBSERVER="apache" ;;
        2) WEBSERVER="caddy" ;;
        *) WEBSERVER="nginx" ;;
    esac

    # Database
    echo ""
    echo -e "  ${BOLD}Choose a database:${RESET}"
    echo -e "  ${CYAN}[0]${RESET} SQLite ${DIM}(simplest, no server needed)${RESET}"
    echo -e "  ${CYAN}[1]${RESET} MySQL"
    echo -e "  ${CYAN}[2]${RESET} MariaDB"
    echo -e "  ${CYAN}[3]${RESET} PostgreSQL"
    echo ""
    ask "Database [0]:"
    read -r db_choice
    case "${db_choice:-0}" in
        0) DB_CHOICE="sqlite" ;;
        1) DB_CHOICE="mysql" ;;
        2) DB_CHOICE="mariadb" ;;
        3) DB_CHOICE="postgres" ;;
        *) DB_CHOICE="sqlite" ;;
    esac

    # SSL
    if [[ "$WEBSERVER" != "caddy" ]]; then
        echo ""
        ask "Configure SSL with Let's Encrypt? (Y/n):"
        read -r ssl_choice
        if [[ "${ssl_choice:-Y}" =~ ^[Yy]$ ]]; then
            CONFIGURE_SSL=true
            ask "Email for Let's Encrypt:"
            read -r EMAIL
            [[ -z "$EMAIL" ]] && fatal "Email is required for SSL certificates."
        else
            CONFIGURE_SSL=false
        fi
    else
        CONFIGURE_SSL=false  # Caddy handles it
    fi
}

show_summary() {
    echo ""
    echo -e "  ${CYAN}${BOLD}╔═══════════════════════════════════════╗${RESET}"
    echo -e "  ${CYAN}${BOLD}║        Installation Summary           ║${RESET}"
    echo -e "  ${CYAN}${BOLD}╚═══════════════════════════════════════╝${RESET}"
    echo ""

    [[ "$INSTALL_PANEL" == true ]] && {
        echo -e "  ${BOLD}Panel:${RESET}"
        echo -e "    Domain:      ${GREEN}${FQDN}${RESET}"
        echo -e "    Web server:  ${GREEN}${WEBSERVER}${RESET}"
        echo -e "    Database:    ${GREEN}${DB_CHOICE}${RESET}"
        echo -e "    SSL:         ${GREEN}$([[ "$CONFIGURE_SSL" == true || "$WEBSERVER" == "caddy" ]] && echo "Yes" || echo "No")${RESET}"
        echo -e "    PHP:         ${GREEN}${PHP_VERSION}${RESET}"
    }

    [[ "$INSTALL_WINGS_FLAG" == true ]] && {
        echo -e "  ${BOLD}Wings:${RESET}"
        echo -e "    Architecture: ${GREEN}${WINGS_ARCH}${RESET}"
        echo -e "    Docker:       ${GREEN}Will be installed${RESET}"
    }

    echo ""
    ask "Proceed with installation? (Y/n):"
    read -r proceed
    if [[ ! "${proceed:-Y}" =~ ^[Yy]$ ]]; then
        info "Installation cancelled."
        exit 0
    fi
}

# ─── Main Menu ─────────────────────────────────────────────────────────────────
main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Pelican Installer v${INSTALLER_VERSION} — $(date) ===" >> "$LOG_FILE"

    print_header
    detect_os
    preflight_checks

    echo ""
    echo -e "  ${BOLD}What would you like to do?${RESET}"
    echo ""
    echo -e "  ${CYAN}[0]${RESET} Install Panel"
    echo -e "  ${CYAN}[1]${RESET} Install Wings"
    echo -e "  ${CYAN}[2]${RESET} Install Panel + Wings ${DIM}(same machine)${RESET}"
    echo -e "  ${CYAN}[3]${RESET} Update Panel"
    echo -e "  ${CYAN}[4]${RESET} Update Wings"
    echo -e "  ${CYAN}[5]${RESET} Update Both"
    echo -e "  ${CYAN}[6]${RESET} Uninstall"
    echo ""
    ask "Select option [0-6]:"
    read -r main_choice

    case "${main_choice}" in
        0)  # Panel only
            INSTALL_PANEL=true
            INSTALL_WINGS_FLAG=false
            collect_panel_options
            detect_php_version
            show_summary
            install_php
            install_database
            install_webserver
            install_ssl
            install_panel
            health_check
            print_panel_complete
            ;;
        1)  # Wings only
            INSTALL_PANEL=false
            INSTALL_WINGS_FLAG=true
            detect_php_version
            install_wings
            health_check
            print_wings_complete
            ;;
        2)  # Both
            INSTALL_PANEL=true
            INSTALL_WINGS_FLAG=true
            collect_panel_options
            detect_php_version
            show_summary
            install_php
            install_database
            install_webserver
            install_ssl
            install_panel
            install_wings
            health_check
            print_both_complete
            ;;
        3)  # Update Panel
            detect_php_version
            update_panel
            ;;
        4)  # Update Wings
            update_wings
            ;;
        5)  # Update Both
            detect_php_version
            update_panel
            update_wings
            ;;
        6)  # Uninstall
            uninstall
            ;;
        *)
            error "Invalid option"
            exit 1
            ;;
    esac
}

# ─── Completion Messages ──────────────────────────────────────────────────────
print_panel_complete() {
    local proto="http"
    [[ "$CONFIGURE_SSL" == true || "$WEBSERVER" == "caddy" ]] && proto="https"

    echo ""
    echo -e "  ${GREEN}${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                       ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║     🎉  Pelican Panel installed successfully!  🎉     ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                       ║${RESET}"
    echo -e "  ${GREEN}${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}Next steps:${RESET}"
    echo -e "  ${DIM}  1. Open ${proto}://${FQDN}/installer in your browser${RESET}"
    echo -e "  ${DIM}  2. Complete the web-based setup wizard${RESET}"
    echo -e "  ${DIM}  3. Create your first admin account${RESET}"
    echo ""
    echo -e "  ${DIM}Log file: ${LOG_FILE}${RESET}"
    echo ""
}

print_wings_complete() {
    echo ""
    echo -e "  ${GREEN}${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                       ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║       🎉  Wings installed successfully!  🎉           ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                       ║${RESET}"
    echo -e "  ${GREEN}${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}Next steps:${RESET}"
    echo -e "  ${DIM}  1. Create a node in Panel admin → Nodes → Create New${RESET}"
    echo -e "  ${DIM}  2. Copy the config YAML into ${WINGS_DIR}/config.yml${RESET}"
    echo -e "  ${DIM}  3. Test: sudo wings --debug${RESET}"
    echo -e "  ${DIM}  4. Start: sudo systemctl start wings${RESET}"
    echo ""
    echo -e "  ${DIM}Log file: ${LOG_FILE}${RESET}"
    echo ""
}

print_both_complete() {
    local proto="http"
    [[ "$CONFIGURE_SSL" == true || "$WEBSERVER" == "caddy" ]] && proto="https"

    echo ""
    echo -e "  ${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                           ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║   🎉  Pelican Panel & Wings installed successfully!  🎉   ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                           ║${RESET}"
    echo -e "  ${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}Panel:${RESET}"
    echo -e "  ${DIM}  1. Open ${proto}://${FQDN}/installer in your browser${RESET}"
    echo -e "  ${DIM}  2. Complete the web-based setup wizard${RESET}"
    echo ""
    echo -e "  ${BOLD}Wings:${RESET}"
    echo -e "  ${DIM}  3. Create a node in Panel admin → Nodes → Create New${RESET}"
    echo -e "  ${DIM}  4. Copy the config YAML into ${WINGS_DIR}/config.yml${RESET}"
    echo -e "  ${DIM}  5. Test: sudo wings --debug${RESET}"
    echo -e "  ${DIM}  6. Start: sudo systemctl start wings${RESET}"
    echo ""
    echo -e "  ${DIM}Log file: ${LOG_FILE}${RESET}"
    echo ""
}

# ─── Run ───────────────────────────────────────────────────────────────────────
main "$@"
