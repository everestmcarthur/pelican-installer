#!/bin/bash

#############################################################################################
#                                                                                           #
#  Pelican Installer — The best way to install Pelican Panel & Wings                        #
#                                                                                           #
#  Copyright (c) 2026, JarvisCLI                                                            #
#  https://github.com/everestmcarthur/pelican-installer                                     #
#                                                                                           #
#  This program is free software: you can redistribute it and/or modify                     #
#  it under the terms of the GNU General Public License v3.0                                #
#                                                                                           #
#  Features:                                                                                #
#    • Full CLI flags for automated/unattended installs                                     #
#    • Every /installer wizard field available as a flag                                    #
#    • Supports Nginx, Apache, and Caddy (auto-SSL) web servers                             #
#    • Full reverse proxy for Wings daemon on all 3 web servers                             #
#    • Supports SQLite, MySQL, MariaDB, and PostgreSQL databases                            #
#    • Redis caching/session/queue support with auto-install                                #
#    • Automatic SSL via Let's Encrypt or Caddy                                             #
#    • Creates admin user automatically (skip web installer entirely)                       #
#    • Writes ALL config to .env — panel works immediately after install                    #
#    • Runs database migrations & seeders automatically                                     #
#    • Post-install health checks & HTTP verification                                       #
#    • Queue worker systemd service + cron auto-setup                                       #
#    • Comprehensive logging to /var/log/pelican-installer.log                              #
#    • Update & Uninstall commands                                                          #
#    • ARM64 support                                                                        #
#    • Single script — no external dependencies                                             #
#                                                                                           #
#############################################################################################

# ═══════════════════════════════════════════════════════════════════════════════
#  Version & Defaults
# ═══════════════════════════════════════════════════════════════════════════════

INSTALLER_VERSION="2.1.0"
PELICAN_PANEL_URL="https://github.com/pelican-dev/panel/releases/latest/download/panel.tar.gz"
PELICAN_WINGS_BASE="https://github.com/pelican-dev/wings/releases/latest/download"

# ── Configurable variables (override via flags or environment) ──

# Paths
PELICAN_DIR="${PELICAN_DIR:-/var/www/pelican}"
WINGS_DIR="${WINGS_DIR:-/etc/pelican}"
WINGS_BIN="${WINGS_BIN:-/usr/local/bin/wings}"
LOG_FILE="${LOG_FILE:-/var/log/pelican-installer.log}"

# Panel basics
FQDN="${FQDN:-}"
WEBSERVER="${WEBSERVER:-}"                   # nginx | apache | caddy
APP_NAME="${APP_NAME:-Pelican}"
APP_URL="${APP_URL:-}"                       # auto-set from FQDN if empty
TIMEZONE="${TIMEZONE:-UTC}"
CONFIGURE_SSL="${CONFIGURE_SSL:-}"           # true | false
EMAIL="${EMAIL:-}"

# Admin user (skip web installer entirely)
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_USER="${ADMIN_USER:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# Database
DB_CHOICE="${DB_CHOICE:-}"                   # sqlite | mysql | mariadb | postgres
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-}"                       # auto-set based on DB_CHOICE if empty
DB_NAME="${DB_NAME:-pelican}"
DB_USER="${DB_USER:-pelican}"
DB_PASSWORD="${DB_PASSWORD:-}"               # auto-generated if empty

# Cache
CACHE_DRIVER="${CACHE_DRIVER:-}"             # file | redis
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_USER="${REDIS_USER:-}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# Session
SESSION_DRIVER="${SESSION_DRIVER:-}"         # file | database | cookie | redis

# Queue
QUEUE_DRIVER="${QUEUE_DRIVER:-}"             # database | redis | sync

# Wings
INSTALL_PANEL="${INSTALL_PANEL:-}"
INSTALL_WINGS_FLAG="${INSTALL_WINGS_FLAG:-}"
WINGS_DOMAIN="${WINGS_DOMAIN:-}"             # FQDN for Wings reverse proxy (e.g., node.example.com)
WINGS_PORT="${WINGS_PORT:-8080}"             # Wings daemon port (default 8080)
WINGS_SSL="${WINGS_SSL:-}"                   # true | false — SSL for Wings reverse proxy
WINGS_PROXY="${WINGS_PROXY:-}"               # true | false — set up reverse proxy for Wings

# General
ASSUME_YES="${ASSUME_YES:-false}"
ACTION="${ACTION:-}"                         # install | update | uninstall

# ═══════════════════════════════════════════════════════════════════════════════
#  Colors & Formatting
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
    WHITE='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' BOLD='' DIM='' RESET=''
fi

CURRENT_STEP=0
TOTAL_STEPS=0

# ═══════════════════════════════════════════════════════════════════════════════
#  Logging & Output
# ═══════════════════════════════════════════════════════════════════════════════

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

print_header() {
    clear 2>/dev/null || true
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

info()    { echo -e "  ${BLUE}ℹ${RESET}  $*"; log "INFO: $*"; }
success() { echo -e "  ${GREEN}✓${RESET}  $*"; log "OK: $*"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $*"; log "WARN: $*"; }
error()   { echo -e "  ${RED}✗${RESET}  $*"; log "ERROR: $*"; }

fatal() {
    echo ""
    echo -e "  ${RED}${BOLD}FATAL:${RESET} ${RED}$*${RESET}"
    log "FATAL: $*"
    echo -e "  ${DIM}Check ${LOG_FILE} for details${RESET}"
    echo ""
    exit 1
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    if [[ $TOTAL_STEPS -gt 0 ]]; then
        echo -e "  ${MAGENTA}${BOLD}[${CURRENT_STEP}/${TOTAL_STEPS}] $*${RESET}"
    else
        echo -e "  ${MAGENTA}${BOLD}▸ $*${RESET}"
    fi
    echo -e "  ${DIM}$(printf '%.0s─' {1..55})${RESET}"
    log "STEP ${CURRENT_STEP}: $*"
}

ask() { echo -e -n "  ${CYAN}?${RESET}  $* "; }

confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    if [[ "$ASSUME_YES" == true ]]; then
        return 0
    fi
    ask "${prompt}"
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
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
    printf "\r  ${CYAN} ${RESET}  %s\n" "$msg"
}

run_cmd() {
    local msg="$1"
    shift
    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    spinner $pid "$msg"
    wait $pid
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "$msg — FAILED (exit code $exit_code)"
        error "Check ${LOG_FILE} for details"
        return $exit_code
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
#  CLI Argument Parsing
# ═══════════════════════════════════════════════════════════════════════════════

show_help() {
    echo ""
    echo "  Pelican Installer v${INSTALLER_VERSION}"
    echo ""
    echo "  Usage: $0 [ACTION] [OPTIONS]"
    echo ""
    echo "  Actions:"
    echo "    install              Install Panel and/or Wings (default)"
    echo "    update               Update Panel and/or Wings"
    echo "    uninstall            Uninstall Panel and/or Wings"
    echo ""
    echo "  Components:"
    echo "    --panel              Install/update Panel"
    echo "    --wings              Install/update Wings"
    echo "    --both               Install/update Panel + Wings"
    echo ""
    echo "  Panel — General:"
    echo "    --domain FQDN       Panel domain name (e.g., panel.example.com)"
    echo "    --app-name NAME     Application name (default: Pelican)"
    echo "    --webserver WS       Web server: nginx, apache, caddy"
    echo "    --ssl                Enable SSL via Let's Encrypt"
    echo "    --no-ssl             Disable SSL"
    echo "    --email EMAIL        Email for Let's Encrypt"
    echo "    --timezone TZ        Timezone (default: UTC)"
    echo ""
    echo "  Panel — Admin User (skip web installer):"
    echo "    --admin-email EMAIL  Admin account email"
    echo "    --admin-user USER    Admin account username"
    echo "    --admin-pass PASS    Admin account password"
    echo ""
    echo "  Panel — Database:"
    echo "    --database DB        Database: sqlite, mysql, mariadb, postgres"
    echo "    --db-host HOST       Database host (default: 127.0.0.1)"
    echo "    --db-port PORT       Database port (auto-detected from db type)"
    echo "    --db-name NAME       Database name (default: pelican)"
    echo "    --db-user USER       Database user (default: pelican)"
    echo "    --db-password PASS   Database password (auto-generated if empty)"
    echo ""
    echo "  Panel — Cache:"
    echo "    --cache-driver DRV   Cache driver: file, redis (default: file)"
    echo "    --redis-host HOST    Redis host (default: 127.0.0.1)"
    echo "    --redis-port PORT    Redis port (default: 6379)"
    echo "    --redis-user USER    Redis username (optional, Redis 6+ ACL)"
    echo "    --redis-password PW  Redis password (optional)"
    echo ""
    echo "  Panel — Session:"
    echo "    --session-driver DRV Session driver: file, database, cookie, redis"
    echo ""
    echo "  Panel — Queue:"
    echo "    --queue-driver DRV   Queue driver: database, redis, sync"
    echo ""
    echo "  Wings:"
    echo "    --wings-domain FQDN  Wings node domain (e.g., node.example.com)"
    echo "    --wings-port PORT    Wings daemon port (default: 8080)"
    echo "    --wings-proxy        Set up web server reverse proxy for Wings"
    echo "    --wings-ssl          Enable SSL for Wings reverse proxy"
    echo ""
    echo "  General:"
    echo "    --yes, -y            Skip all confirmation prompts"
    echo "    --help, -h           Show this help"
    echo ""
    echo "  Examples:"
    echo ""
    echo "    # Interactive install"
    echo "    sudo bash install.sh"
    echo ""
    echo "    # Fully automated panel install (skip web installer entirely)"
    echo "    sudo bash install.sh install --panel --domain panel.example.com \\"
    echo "         --webserver nginx --database postgres --ssl --email you@example.com \\"
    echo "         --cache-driver redis --session-driver redis --queue-driver redis \\"
    echo "         --admin-email admin@example.com --admin-user admin --admin-pass S3cure! \\"
    echo "         --timezone America/New_York -y"
    echo ""
    echo "    # Panel + Wings with Wings reverse proxy"
    echo "    sudo bash install.sh install --both --domain panel.example.com \\"
    echo "         --wings-domain node.example.com --wings-proxy --wings-ssl \\"
    echo "         --webserver nginx --database postgres --ssl --email you@example.com -y"
    echo ""
    echo "    # Wings only with Caddy reverse proxy"
    echo "    sudo bash install.sh install --wings --wings-domain node.example.com \\"
    echo "         --wings-proxy --webserver caddy -y"
    echo ""
    echo "    # Update everything"
    echo "    sudo bash install.sh update --both -y"
    echo ""
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|update|uninstall)
                ACTION="$1" ;;
            --panel)
                INSTALL_PANEL=true ;;
            --wings)
                INSTALL_WINGS_FLAG=true ;;
            --both)
                INSTALL_PANEL=true; INSTALL_WINGS_FLAG=true ;;
            --domain|--fqdn)
                FQDN="$2"; shift ;;
            --app-name)
                APP_NAME="$2"; shift ;;
            --webserver|--ws)
                WEBSERVER="$2"; shift ;;
            --database|--db)
                DB_CHOICE="$2"; shift ;;
            --db-host)
                DB_HOST="$2"; shift ;;
            --db-port)
                DB_PORT="$2"; shift ;;
            --db-name)
                DB_NAME="$2"; shift ;;
            --db-user)
                DB_USER="$2"; shift ;;
            --db-password|--db-pass)
                DB_PASSWORD="$2"; shift ;;
            --ssl)
                CONFIGURE_SSL=true ;;
            --no-ssl)
                CONFIGURE_SSL=false ;;
            --email)
                EMAIL="$2"; shift ;;
            --timezone|--tz)
                TIMEZONE="$2"; shift ;;
            --admin-email)
                ADMIN_EMAIL="$2"; shift ;;
            --admin-user|--admin-username)
                ADMIN_USER="$2"; shift ;;
            --admin-pass|--admin-password)
                ADMIN_PASSWORD="$2"; shift ;;
            --cache-driver|--cache)
                CACHE_DRIVER="$2"; shift ;;
            --redis-host)
                REDIS_HOST="$2"; shift ;;
            --redis-port)
                REDIS_PORT="$2"; shift ;;
            --redis-user|--redis-username)
                REDIS_USER="$2"; shift ;;
            --redis-password|--redis-pass)
                REDIS_PASSWORD="$2"; shift ;;
            --session-driver|--session)
                SESSION_DRIVER="$2"; shift ;;
            --queue-driver|--queue)
                QUEUE_DRIVER="$2"; shift ;;
            --wings-domain)
                WINGS_DOMAIN="$2"; shift ;;
            --wings-port)
                WINGS_PORT="$2"; shift ;;
            --wings-proxy)
                WINGS_PROXY=true ;;
            --wings-ssl)
                WINGS_SSL=true ;;
            --yes|-y)
                ASSUME_YES=true ;;
            --help|-h)
                show_help ;;
            *)
                warn "Unknown option: $1" ;;
        esac
        shift
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  OS Detection
# ═══════════════════════════════════════════════════════════════════════════════

detect_os() {
    step "Detecting system environment"

    if [[ ! -f /etc/os-release ]]; then
        fatal "Cannot detect operating system — /etc/os-release not found."
    fi

    . /etc/os-release
    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"
    OS_NAME="$PRETTY_NAME"

    case "$OS_ID" in
        ubuntu|debian)
            OS_FAMILY="debian"; PKG_MANAGER="apt" ;;
        almalinux|rocky|centos|rhel)
            OS_FAMILY="rhel"; PKG_MANAGER="dnf" ;;
        *)
            if command -v apt &>/dev/null; then
                OS_FAMILY="debian"; PKG_MANAGER="apt"
                warn "Unknown OS '$OS_ID' — detected apt, proceeding as Debian-like"
            elif command -v dnf &>/dev/null; then
                OS_FAMILY="rhel"; PKG_MANAGER="dnf"
                warn "Unknown OS '$OS_ID' — detected dnf, proceeding as RHEL-like"
            else
                fatal "Unsupported OS: $OS_ID (no apt or dnf found)"
            fi
            ;;
    esac

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)          WINGS_ARCH="amd64" ;;
        aarch64|arm64)   WINGS_ARCH="arm64" ;;
        *)               fatal "Unsupported architecture: $ARCH" ;;
    esac

    success "OS: ${BOLD}$OS_NAME${RESET} ($OS_FAMILY/$PKG_MANAGER)"
    success "Architecture: ${BOLD}$ARCH${RESET} → Wings binary: $WINGS_ARCH"

    # Detect web server user (updated later when WEBSERVER is chosen)
    update_webserver_user
}

update_webserver_user() {
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        case "${WEBSERVER:-nginx}" in
            nginx)  WEBSERVER_USER="nginx" ;;
            apache) WEBSERVER_USER="apache" ;;
            caddy)  WEBSERVER_USER="caddy" ;;
            *)      WEBSERVER_USER="nginx" ;;
        esac
    else
        WEBSERVER_USER="www-data"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Preflight Checks
# ═══════════════════════════════════════════════════════════════════════════════

preflight_checks() {
    step "Running preflight checks"

    # Root check
    if [[ $EUID -ne 0 ]]; then
        fatal "This script must be run as root. Use: sudo bash $0"
    fi
    success "Running as root"

    # Essential tools
    for cmd in curl tar openssl; do
        if ! command -v "$cmd" &>/dev/null; then
            info "Installing $cmd..."
            $PKG_MANAGER install -y "$cmd" >> "$LOG_FILE" 2>&1 || fatal "Failed to install $cmd"
        fi
        success "$cmd available"
    done

    # Virtualization check (for Wings)
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null || echo "none")
        if [[ "$virt" == "openvz" || "$virt" == "lxc" ]]; then
            warn "Detected ${BOLD}$virt${RESET} — Docker/Wings may not work without nested virt"
        else
            success "Virtualization: $virt"
        fi
    fi

    # Memory
    local total_mem
    total_mem=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
    if [[ $total_mem -lt 1024 ]]; then
        warn "Low memory: ${total_mem}MB (1GB+ recommended)"
    else
        success "Memory: ${total_mem}MB"
    fi

    # Disk
    local free_disk
    free_disk=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $free_disk -lt 5 ]]; then
        warn "Low disk: ${free_disk}GB free (10GB+ recommended)"
    else
        success "Disk: ${free_disk}GB free"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PHP Installation
# ═══════════════════════════════════════════════════════════════════════════════

detect_php_version() {
    for ver in 8.4 8.3 8.2; do
        if [[ "$OS_FAMILY" == "debian" ]]; then
            if apt-cache show "php${ver}-fpm" &>/dev/null 2>&1; then
                PHP_VERSION="$ver"; return
            fi
        else
            if dnf list "php" 2>/dev/null | grep -q "$ver"; then
                PHP_VERSION="$ver"; return
            fi
        fi
    done
    PHP_VERSION="8.3"
}

install_php() {
    step "Installing PHP $PHP_VERSION & extensions"

    if [[ "$OS_FAMILY" == "debian" ]]; then
        # Add PHP repo
        if ! command -v add-apt-repository &>/dev/null; then
            apt install -y software-properties-common >> "$LOG_FILE" 2>&1
        fi

        if [[ "$OS_ID" == "ubuntu" ]]; then
            add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1 || true
        elif [[ "$OS_ID" == "debian" ]]; then
            apt install -y lsb-release apt-transport-https ca-certificates >> "$LOG_FILE" 2>&1
            curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb >> "$LOG_FILE" 2>&1
            dpkg -i /tmp/debsuryorg-archive-keyring.deb >> "$LOG_FILE" 2>&1
            echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
                > /etc/apt/sources.list.d/sury-php.list
        fi

        run_cmd "Updating package lists" apt update

        local pkgs=(
            "php${PHP_VERSION}" "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-common"
            "php${PHP_VERSION}-cli" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-mysql"
            "php${PHP_VERSION}-pgsql" "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-bcmath"
            "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip"
            "php${PHP_VERSION}-intl" "php${PHP_VERSION}-sqlite3" "php${PHP_VERSION}-tokenizer"
            "php${PHP_VERSION}-fileinfo" "php${PHP_VERSION}-dom" "php${PHP_VERSION}-redis"
        )

        run_cmd "Installing PHP ${PHP_VERSION} and extensions" apt install -y "${pkgs[@]}"

    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf install -y epel-release >> "$LOG_FILE" 2>&1
        dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm" >> "$LOG_FILE" 2>&1 || true
        dnf module reset php -y >> "$LOG_FILE" 2>&1 || true
        dnf module enable "php:remi-${PHP_VERSION}" -y >> "$LOG_FILE" 2>&1 || true

        run_cmd "Installing PHP ${PHP_VERSION} and extensions" dnf install -y \
            php php-fpm php-common php-cli php-gd php-mysqlnd php-pgsql \
            php-mbstring php-bcmath php-xml php-curl php-zip php-intl php-pdo \
            php-tokenizer php-redis
    fi

    # Configure PHP-FPM pool
    local fpm_conf=""
    if [[ "$OS_FAMILY" == "debian" ]]; then
        fpm_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    else
        fpm_conf="/etc/php-fpm.d/www.conf"
    fi

    if [[ -f "$fpm_conf" ]]; then
        sed -i "s/^user = .*/user = ${WEBSERVER_USER}/" "$fpm_conf"
        sed -i "s/^group = .*/group = ${WEBSERVER_USER}/" "$fpm_conf"
        sed -i "s/^listen.owner = .*/listen.owner = ${WEBSERVER_USER}/" "$fpm_conf"
        sed -i "s/^listen.group = .*/listen.group = ${WEBSERVER_USER}/" "$fpm_conf"
        success "PHP-FPM pool configured for ${WEBSERVER_USER}"
    fi

    systemctl enable --now "php${PHP_VERSION}-fpm" >> "$LOG_FILE" 2>&1 || \
        systemctl enable --now php-fpm >> "$LOG_FILE" 2>&1 || true
    success "PHP-FPM started and enabled"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Redis Installation
# ═══════════════════════════════════════════════════════════════════════════════

needs_redis() {
    [[ "$CACHE_DRIVER" == "redis" || "$SESSION_DRIVER" == "redis" || "$QUEUE_DRIVER" == "redis" ]]
}

install_redis() {
    if ! needs_redis; then
        return
    fi

    # Only install if using localhost and redis isn't already running
    if [[ "$REDIS_HOST" == "127.0.0.1" || "$REDIS_HOST" == "localhost" || "$REDIS_HOST" == "::1" ]]; then
        if command -v redis-server &>/dev/null && systemctl is-active --quiet redis-server 2>/dev/null; then
            success "Redis is already installed and running"
        else
            step "Installing Redis"
            if [[ "$OS_FAMILY" == "debian" ]]; then
                run_cmd "Installing Redis server" apt install -y redis-server
            else
                run_cmd "Installing Redis server" dnf install -y redis
            fi

            # Configure Redis password if set
            if [[ -n "$REDIS_PASSWORD" ]]; then
                local redis_conf="/etc/redis/redis.conf"
                [[ ! -f "$redis_conf" ]] && redis_conf="/etc/redis.conf"
                if [[ -f "$redis_conf" ]]; then
                    sed -i "s/^# requirepass .*/requirepass ${REDIS_PASSWORD}/" "$redis_conf"
                    sed -i "s/^requirepass .*/requirepass ${REDIS_PASSWORD}/" "$redis_conf"
                    success "Redis password configured"
                fi
            fi

            systemctl enable --now redis-server >> "$LOG_FILE" 2>&1 || \
                systemctl enable --now redis >> "$LOG_FILE" 2>&1
            success "Redis installed and running"
        fi
    else
        info "Redis host is ${REDIS_HOST} — skipping local Redis install"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Database Installation
# ═══════════════════════════════════════════════════════════════════════════════

generate_db_password() {
    if [[ -z "$DB_PASSWORD" && "$DB_CHOICE" != "sqlite" ]]; then
        DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
        log "Generated DB password: $DB_PASSWORD"
    fi
}

auto_set_db_port() {
    if [[ -z "$DB_PORT" ]]; then
        case "$DB_CHOICE" in
            mysql|mariadb) DB_PORT="3306" ;;
            postgres)      DB_PORT="5432" ;;
            sqlite)        DB_PORT="" ;;
        esac
    fi
}

install_database() {
    if [[ "$DB_CHOICE" == "sqlite" ]]; then
        info "Using SQLite — no database server needed"
        return
    fi

    step "Installing ${DB_CHOICE^} database server"

    case "$DB_CHOICE" in
        mysql)
            if [[ "$OS_FAMILY" == "debian" ]]; then
                run_cmd "Installing MySQL" apt install -y mysql-server mysql-client
            else
                run_cmd "Installing MySQL" dnf install -y mysql-server
            fi
            systemctl enable --now mysql >> "$LOG_FILE" 2>&1 || systemctl enable --now mysqld >> "$LOG_FILE" 2>&1
            success "MySQL installed and running"
            ;;
        mariadb)
            if [[ "$OS_FAMILY" == "debian" ]]; then
                run_cmd "Installing MariaDB" apt install -y mariadb-server mariadb-client
            else
                run_cmd "Installing MariaDB" dnf install -y mariadb-server
            fi
            systemctl enable --now mariadb >> "$LOG_FILE" 2>&1
            success "MariaDB installed and running"
            ;;
        postgres)
            if [[ "$OS_FAMILY" == "debian" ]]; then
                run_cmd "Installing PostgreSQL" apt install -y postgresql postgresql-client
            else
                run_cmd "Installing PostgreSQL" dnf install -y postgresql-server postgresql
                postgresql-setup --initdb >> "$LOG_FILE" 2>&1 || true
            fi
            systemctl enable --now postgresql >> "$LOG_FILE" 2>&1
            success "PostgreSQL installed and running"
            ;;
    esac

    setup_database
}

setup_database() {
    step "Creating database & user"

    generate_db_password
    auto_set_db_port

    case "$DB_CHOICE" in
        mysql|mariadb)
            mysql -u root <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOSQL
            if [[ $? -ne 0 ]]; then
                fatal "Failed to create MySQL/MariaDB database. Check ${LOG_FILE}"
            fi
            success "Database '${DB_NAME}' created with user '${DB_USER}'"
            ;;

        postgres)
            # Create user and database
            sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';" >> "$LOG_FILE" 2>&1 || {
                sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';" >> "$LOG_FILE" 2>&1
            }
            sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" >> "$LOG_FILE" 2>&1 || {
                sudo -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};" >> "$LOG_FILE" 2>&1
            }
            sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" >> "$LOG_FILE" 2>&1

            # CRITICAL: Configure pg_hba.conf for password auth over TCP
            local pg_hba
            pg_hba=$(sudo -u postgres psql -t -c "SHOW hba_file;" 2>/dev/null | xargs)
            if [[ -n "$pg_hba" && -f "$pg_hba" ]]; then
                if ! grep -q "${DB_USER}" "$pg_hba" 2>/dev/null; then
                    sed -i "/^# IPv4 local connections:/a host    ${DB_NAME}    ${DB_USER}    127.0.0.1/32    md5" "$pg_hba"
                    sed -i "/^# IPv6 local connections:/a host    ${DB_NAME}    ${DB_USER}    ::1/128         md5" "$pg_hba"
                    success "pg_hba.conf configured for password authentication"
                    systemctl reload postgresql >> "$LOG_FILE" 2>&1
                fi
            else
                for hba_path in /etc/postgresql/*/main/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf; do
                    if [[ -f "$hba_path" ]]; then
                        if ! grep -q "${DB_USER}" "$hba_path"; then
                            sed -i "/^# IPv4 local connections:/a host    ${DB_NAME}    ${DB_USER}    127.0.0.1/32    md5" "$hba_path"
                            sed -i "/^# IPv6 local connections:/a host    ${DB_NAME}    ${DB_USER}    ::1/128         md5" "$hba_path"
                        fi
                        break
                    fi
                done
                systemctl reload postgresql >> "$LOG_FILE" 2>&1
                success "pg_hba.conf configured for password authentication"
            fi

            success "PostgreSQL database '${DB_NAME}' created with user '${DB_USER}'"
            ;;
    esac

    # Show credentials in a visible box
    echo ""
    echo -e "  ${GREEN}${BOLD}┌─────────────────────────────────────────────┐${RESET}"
    echo -e "  ${GREEN}${BOLD}│  DATABASE CREDENTIALS — SAVE THESE!         │${RESET}"
    echo -e "  ${GREEN}${BOLD}├─────────────────────────────────────────────┤${RESET}"
    echo -e "  ${GREEN}${BOLD}│${RESET}  Host:     ${WHITE}${DB_HOST}${RESET}"
    echo -e "  ${GREEN}${BOLD}│${RESET}  Port:     ${WHITE}${DB_PORT}${RESET}"
    echo -e "  ${GREEN}${BOLD}│${RESET}  Database: ${WHITE}${DB_NAME}${RESET}"
    echo -e "  ${GREEN}${BOLD}│${RESET}  User:     ${WHITE}${DB_USER}${RESET}"
    echo -e "  ${GREEN}${BOLD}│${RESET}  Password: ${WHITE}${DB_PASSWORD}${RESET}"
    echo -e "  ${GREEN}${BOLD}└─────────────────────────────────────────────┘${RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Web Server Installation
# ═══════════════════════════════════════════════════════════════════════════════

get_fpm_socket() {
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        echo "/run/php-fpm/www.sock"
    else
        echo "/run/php/php${PHP_VERSION}-fpm.sock"
    fi
}

install_webserver() {
    step "Installing ${WEBSERVER^} web server"

    case "$WEBSERVER" in
        nginx)  install_nginx ;;
        apache) install_apache ;;
        caddy)  install_caddy ;;
    esac
}

# ── Nginx ────────────────────────────────────────────────────────────────────

install_nginx() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        run_cmd "Installing Nginx" apt install -y nginx
    else
        run_cmd "Installing Nginx" dnf install -y nginx
    fi

    rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf 2>/dev/null || true
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null || true

    # Ensure sites-enabled is included on RHEL
    if [[ "$OS_FAMILY" == "rhel" ]] && ! grep -q "sites-enabled" /etc/nginx/nginx.conf 2>/dev/null; then
        sed -i '/http {/a \    include /etc/nginx/sites-enabled/*.conf;' /etc/nginx/nginx.conf
    fi

    local fpm_sock
    fpm_sock=$(get_fpm_socket)

    if [[ "$INSTALL_PANEL" == true ]]; then
        write_nginx_panel_config "$fpm_sock"
        ln -sf /etc/nginx/sites-available/pelican.conf /etc/nginx/sites-enabled/pelican.conf
        success "Nginx panel vhost configured for ${FQDN}"
    fi

    if [[ "$WINGS_PROXY" == true && -n "$WINGS_DOMAIN" ]]; then
        write_nginx_wings_config
        ln -sf /etc/nginx/sites-available/wings.conf /etc/nginx/sites-enabled/wings.conf
        success "Nginx wings reverse proxy configured for ${WINGS_DOMAIN}"
    fi

    nginx -t >> "$LOG_FILE" 2>&1 || warn "Nginx config test failed — check ${LOG_FILE}"
    systemctl enable --now nginx >> "$LOG_FILE" 2>&1
    systemctl restart nginx >> "$LOG_FILE" 2>&1
    success "Nginx configured and running"
}

write_nginx_panel_config() {
    local fpm_sock="$1"

    if [[ "$CONFIGURE_SSL" == true ]]; then
        cat > /etc/nginx/sites-available/pelican.conf <<NGINXCFG
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

    access_log /var/log/nginx/pelican.access.log;
    error_log  /var/log/nginx/pelican.error.log error;

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
NGINXCFG
    else
        cat > /etc/nginx/sites-available/pelican.conf <<NGINXCFG
server_tokens off;

server {
    listen 80;
    server_name ${FQDN};

    root ${PELICAN_DIR}/public;
    index index.php;

    access_log /var/log/nginx/pelican.access.log;
    error_log  /var/log/nginx/pelican.error.log error;

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
NGINXCFG
    fi
}

write_nginx_wings_config() {
    if [[ "$WINGS_SSL" == true ]]; then
        cat > /etc/nginx/sites-available/wings.conf <<WINGSCFG
server {
    listen 80;
    server_name ${WINGS_DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${WINGS_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${WINGS_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${WINGS_DOMAIN}/privkey.pem;
    ssl_session_cache shared:WingsSSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";
    ssl_prefer_server_ciphers on;

    # Websocket support (console, file manager, etc.)
    location ~ /api/servers/(?<server>[a-f0-9-]+)/ws\$ {
        proxy_pass http://127.0.0.1:${WINGS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location / {
        proxy_pass http://127.0.0.1:${WINGS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 0;
    }
}
WINGSCFG
    else
        cat > /etc/nginx/sites-available/wings.conf <<WINGSCFG
server {
    listen 80;
    server_name ${WINGS_DOMAIN};

    # Websocket support (console, file manager, etc.)
    location ~ /api/servers/(?<server>[a-f0-9-]+)/ws\$ {
        proxy_pass http://127.0.0.1:${WINGS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location / {
        proxy_pass http://127.0.0.1:${WINGS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 0;
    }
}
WINGSCFG
    fi
}

# ── Apache ───────────────────────────────────────────────────────────────────

install_apache() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        run_cmd "Installing Apache" apt install -y apache2 "libapache2-mod-php${PHP_VERSION}"
        a2enmod rewrite ssl headers proxy proxy_fcgi proxy_http proxy_wstunnel >> "$LOG_FILE" 2>&1 || true
        a2dissite 000-default >> "$LOG_FILE" 2>&1 || true
    else
        run_cmd "Installing Apache" dnf install -y httpd mod_ssl
    fi

    local fpm_sock
    fpm_sock=$(get_fpm_socket)
    local conf_dir="/etc/apache2/sites-available"
    [[ "$OS_FAMILY" == "rhel" ]] && conf_dir="/etc/httpd/conf.d"

    if [[ "$INSTALL_PANEL" == true ]]; then
        write_apache_panel_config "$conf_dir" "$fpm_sock"
        if [[ "$OS_FAMILY" == "debian" ]]; then
            a2ensite pelican >> "$LOG_FILE" 2>&1
        fi
        success "Apache panel vhost configured for ${FQDN}"
    fi

    if [[ "$WINGS_PROXY" == true && -n "$WINGS_DOMAIN" ]]; then
        write_apache_wings_config "$conf_dir"
        if [[ "$OS_FAMILY" == "debian" ]]; then
            a2ensite wings >> "$LOG_FILE" 2>&1
        fi
        success "Apache wings reverse proxy configured for ${WINGS_DOMAIN}"
    fi

    if [[ "$OS_FAMILY" == "debian" ]]; then
        systemctl enable --now apache2 >> "$LOG_FILE" 2>&1
        systemctl restart apache2 >> "$LOG_FILE" 2>&1
    else
        systemctl enable --now httpd >> "$LOG_FILE" 2>&1
        systemctl restart httpd >> "$LOG_FILE" 2>&1
    fi
    success "Apache configured and running"
}

write_apache_panel_config() {
    local conf_dir="$1"
    local fpm_sock="$2"

    if [[ "$CONFIGURE_SSL" == true ]]; then
        cat > "${conf_dir}/pelican.conf" <<APACHECFG
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
APACHECFG
    else
        cat > "${conf_dir}/pelican.conf" <<APACHECFG
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
APACHECFG
    fi
}

write_apache_wings_config() {
    local conf_dir="$1"

    if [[ "$WINGS_SSL" == true ]]; then
        cat > "${conf_dir}/wings.conf" <<WINGSCFG
<VirtualHost *:80>
    ServerName ${WINGS_DOMAIN}
    Redirect permanent / https://${WINGS_DOMAIN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${WINGS_DOMAIN}

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${WINGS_DOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${WINGS_DOMAIN}/privkey.pem

    SSLProxyEngine On
    ProxyPreserveHost On

    # Websocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/(.*) ws://127.0.0.1:${WINGS_PORT}/\$1 [P,L]

    ProxyPass / http://127.0.0.1:${WINGS_PORT}/
    ProxyPassReverse / http://127.0.0.1:${WINGS_PORT}/

    RequestHeader set X-Forwarded-Proto "https"
</VirtualHost>
WINGSCFG
    else
        cat > "${conf_dir}/wings.conf" <<WINGSCFG
<VirtualHost *:80>
    ServerName ${WINGS_DOMAIN}

    ProxyPreserveHost On

    # Websocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/(.*) ws://127.0.0.1:${WINGS_PORT}/\$1 [P,L]

    ProxyPass / http://127.0.0.1:${WINGS_PORT}/
    ProxyPassReverse / http://127.0.0.1:${WINGS_PORT}/

    RequestHeader set X-Forwarded-Proto "http"
</VirtualHost>
WINGSCFG
    fi
}

# ── Caddy ────────────────────────────────────────────────────────────────────

install_caddy() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt install -y debian-keyring debian-archive-keyring apt-transport-https >> "$LOG_FILE" 2>&1
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | \
            gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | \
            tee /etc/apt/sources.list.d/caddy-stable.list >> "$LOG_FILE" 2>&1
        apt update >> "$LOG_FILE" 2>&1
        run_cmd "Installing Caddy" apt install -y caddy
    else
        dnf install -y 'dnf-command(copr)' >> "$LOG_FILE" 2>&1
        dnf copr enable @caddy/caddy -y >> "$LOG_FILE" 2>&1
        run_cmd "Installing Caddy" dnf install -y caddy
    fi

    local fpm_sock
    fpm_sock=$(get_fpm_socket)

    # Build Caddyfile with panel + optional wings
    {
        if [[ "$INSTALL_PANEL" == true ]]; then
            cat <<CADDYPANEL
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
CADDYPANEL
        fi

        if [[ "$WINGS_PROXY" == true && -n "$WINGS_DOMAIN" ]]; then
            cat <<CADDYWINGS

${WINGS_DOMAIN} {
    reverse_proxy 127.0.0.1:${WINGS_PORT} {
        # Flush for websockets (console, file manager)
        flush_interval -1

        # Unlimited upload size for server files
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    # Websocket handling is automatic in Caddy

    log {
        output file /var/log/caddy/wings.log
    }
}
CADDYWINGS
        fi
    } > /etc/caddy/Caddyfile

    mkdir -p /var/log/caddy
    systemctl enable --now caddy >> "$LOG_FILE" 2>&1
    systemctl restart caddy >> "$LOG_FILE" 2>&1

    [[ "$INSTALL_PANEL" == true ]] && success "Caddy panel vhost configured for ${FQDN} (auto-SSL)"
    [[ "$WINGS_PROXY" == true && -n "$WINGS_DOMAIN" ]] && success "Caddy wings reverse proxy configured for ${WINGS_DOMAIN} (auto-SSL)"
    success "Caddy configured and running"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SSL (Let's Encrypt)
# ═══════════════════════════════════════════════════════════════════════════════

install_ssl() {
    if [[ "$CONFIGURE_SSL" != true && "$WINGS_SSL" != true ]]; then
        return
    fi
    if [[ "$WEBSERVER" == "caddy" ]]; then
        info "Caddy handles SSL automatically — skipping certbot"
        return
    fi

    step "Obtaining SSL certificate(s) via Let's Encrypt"

    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt install -y certbot >> "$LOG_FILE" 2>&1
        [[ "$WEBSERVER" == "nginx" ]]  && apt install -y python3-certbot-nginx >> "$LOG_FILE" 2>&1
        [[ "$WEBSERVER" == "apache" ]] && apt install -y python3-certbot-apache >> "$LOG_FILE" 2>&1
    else
        dnf install -y certbot >> "$LOG_FILE" 2>&1
        [[ "$WEBSERVER" == "nginx" ]]  && dnf install -y python3-certbot-nginx >> "$LOG_FILE" 2>&1
        [[ "$WEBSERVER" == "apache" ]] && dnf install -y python3-certbot-apache >> "$LOG_FILE" 2>&1
    fi

    local plugin="--standalone"
    [[ "$WEBSERVER" == "nginx" ]]  && plugin="--nginx"
    [[ "$WEBSERVER" == "apache" ]] && plugin="--apache"

    # Collect all domains that need certs
    local domains=()
    [[ "$CONFIGURE_SSL" == true && -n "$FQDN" ]] && domains+=("$FQDN")
    [[ "$WINGS_SSL" == true && -n "$WINGS_DOMAIN" && "$WINGS_DOMAIN" != "$FQDN" ]] && domains+=("$WINGS_DOMAIN")

    for domain in "${domains[@]}"; do
        info "Requesting certificate for ${domain}..."
        certbot certonly $plugin -d "$domain" --non-interactive --agree-tos --email "$EMAIL" >> "$LOG_FILE" 2>&1 || {
            warn "Plugin-based cert for $domain failed, trying standalone..."
            systemctl stop nginx 2>/dev/null; systemctl stop apache2 2>/dev/null; systemctl stop httpd 2>/dev/null
            certbot certonly --standalone -d "$domain" --non-interactive --agree-tos --email "$EMAIL" >> "$LOG_FILE" 2>&1 || \
                error "Failed to obtain SSL certificate for $domain — is the domain pointed to this server?"
            systemctl start nginx 2>/dev/null || systemctl start apache2 2>/dev/null || systemctl start httpd 2>/dev/null
        }
        success "SSL certificate obtained for ${domain}"
    done

    # Auto-renewal cron
    local restart_svc="$WEBSERVER"
    [[ "$WEBSERVER" == "apache" && "$OS_FAMILY" == "debian" ]] && restart_svc="apache2"
    [[ "$WEBSERVER" == "apache" && "$OS_FAMILY" == "rhel" ]] && restart_svc="httpd"
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --deploy-hook \"systemctl restart ${restart_svc}\"") | sort -u | crontab -
    success "Auto-renewal cron configured"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Pelican Panel Installation
# ═══════════════════════════════════════════════════════════════════════════════

install_panel() {
    step "Downloading Pelican Panel"

    mkdir -p "$PELICAN_DIR"
    cd "$PELICAN_DIR"

    run_cmd "Downloading and extracting Pelican Panel" bash -c "curl -sSL '$PELICAN_PANEL_URL' | tar -xzv >> '$LOG_FILE' 2>&1"
    success "Panel files downloaded to ${PELICAN_DIR}"

    step "Installing Composer & PHP dependencies"

    if ! command -v composer &>/dev/null; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >> "$LOG_FILE" 2>&1
        success "Composer installed"
    fi

    run_cmd "Installing PHP dependencies (this takes ~1 minute)" \
        env COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --working-dir="$PELICAN_DIR"
    success "Composer dependencies installed"

    step "Configuring Pelican Panel"

    configure_env_file
    run_database_setup
    set_permissions
    create_admin_user
    setup_queue_worker
    setup_cron_job

    # Show APP_KEY warning
    local app_key
    app_key=$(grep "^APP_KEY=" "${PELICAN_DIR}/.env" 2>/dev/null | cut -d= -f2-)
    if [[ -n "$app_key" ]]; then
        echo ""
        echo -e "  ${RED}${BOLD}┌─────────────────────────────────────────────────────────┐${RESET}"
        echo -e "  ${RED}${BOLD}│  ⚠  ENCRYPTION KEY — BACK THIS UP! LOSING IT = DATA LOSS│${RESET}"
        echo -e "  ${RED}${BOLD}├─────────────────────────────────────────────────────────┤${RESET}"
        echo -e "  ${RED}${BOLD}│${RESET}  APP_KEY=${WHITE}${app_key}${RESET}"
        echo -e "  ${RED}${BOLD}└─────────────────────────────────────────────────────────┘${RESET}"
        echo ""
    fi
}

configure_env_file() {
    info "Writing .env configuration..."

    # Determine APP_URL
    if [[ -z "$APP_URL" ]]; then
        if [[ "$CONFIGURE_SSL" == true || "$WEBSERVER" == "caddy" ]]; then
            APP_URL="https://${FQDN}"
        else
            APP_URL="http://${FQDN}"
        fi
    fi

    # Determine DB connection string for Laravel
    local laravel_db_connection
    case "$DB_CHOICE" in
        mysql)    laravel_db_connection="mysql" ;;
        mariadb)  laravel_db_connection="mariadb" ;;
        postgres) laravel_db_connection="pgsql" ;;
        sqlite)   laravel_db_connection="sqlite" ;;
    esac

    # Set defaults for session/cache/queue if not set
    CACHE_DRIVER="${CACHE_DRIVER:-file}"
    SESSION_DRIVER="${SESSION_DRIVER:-file}"
    QUEUE_DRIVER="${QUEUE_DRIVER:-database}"

    # Copy example .env if needed
    if [[ ! -f "${PELICAN_DIR}/.env" && -f "${PELICAN_DIR}/.env.example" ]]; then
        cp "${PELICAN_DIR}/.env.example" "${PELICAN_DIR}/.env"
    fi

    # Generate APP_KEY
    cd "$PELICAN_DIR"
    php artisan key:generate --force --no-interaction >> "$LOG_FILE" 2>&1
    success "Application key generated"

    # Helper to set a value in .env
    set_env() {
        local key="$1"
        local value="$2"
        if grep -q "^${key}=" "${PELICAN_DIR}/.env" 2>/dev/null; then
            # Escape special chars in value for sed
            local escaped_value
            escaped_value=$(printf '%s' "$value" | sed 's/[&/\]/\\&/g')
            sed -i "s|^${key}=.*|${key}=${escaped_value}|" "${PELICAN_DIR}/.env"
        else
            echo "${key}=${value}" >> "${PELICAN_DIR}/.env"
        fi
    }

    # ── Core settings ──
    set_env "APP_NAME" "$APP_NAME"
    set_env "APP_URL" "$APP_URL"
    set_env "APP_TIMEZONE" "$TIMEZONE"
    set_env "APP_ENV" "production"
    set_env "APP_DEBUG" "false"

    # ── Database settings ──
    set_env "DB_CONNECTION" "$laravel_db_connection"

    if [[ "$DB_CHOICE" == "sqlite" ]]; then
        set_env "DB_DATABASE" "${PELICAN_DIR}/database/database.sqlite"
        touch "${PELICAN_DIR}/database/database.sqlite"
    else
        set_env "DB_HOST" "$DB_HOST"
        set_env "DB_PORT" "$DB_PORT"
        set_env "DB_DATABASE" "$DB_NAME"
        set_env "DB_USERNAME" "$DB_USER"
        set_env "DB_PASSWORD" "$DB_PASSWORD"
    fi

    # ── Cache settings ──
    set_env "CACHE_STORE" "$CACHE_DRIVER"

    if [[ "$CACHE_DRIVER" == "redis" ]]; then
        set_env "REDIS_HOST" "$REDIS_HOST"
        set_env "REDIS_PORT" "$REDIS_PORT"
        [[ -n "$REDIS_USER" ]]     && set_env "REDIS_USERNAME" "$REDIS_USER"
        [[ -n "$REDIS_PASSWORD" ]] && set_env "REDIS_PASSWORD" "$REDIS_PASSWORD"
    fi

    # ── Session settings ──
    set_env "SESSION_DRIVER" "$SESSION_DRIVER"

    local session_secure="false"
    [[ "$CONFIGURE_SSL" == true || "$WEBSERVER" == "caddy" ]] && session_secure="true"
    set_env "SESSION_SECURE_COOKIE" "$session_secure"

    # ── Queue settings ──
    set_env "QUEUE_CONNECTION" "$QUEUE_DRIVER"

    success ".env configured with all panel settings"
    log "ENV: APP_URL=$APP_URL DB=$laravel_db_connection CACHE=$CACHE_DRIVER SESSION=$SESSION_DRIVER QUEUE=$QUEUE_DRIVER"
}

run_database_setup() {
    info "Running database migrations..."

    cd "$PELICAN_DIR"

    php artisan migrate --seed --force >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        error "Database migration failed — check ${LOG_FILE}"
        error "You can retry manually: cd ${PELICAN_DIR} && php artisan migrate --seed --force"
    else
        success "Database migrations and seeders completed"
    fi
}

set_permissions() {
    info "Setting file permissions..."

    chown -R "${WEBSERVER_USER}:${WEBSERVER_USER}" "$PELICAN_DIR"
    chmod -R 775 "${PELICAN_DIR}/storage" "${PELICAN_DIR}/bootstrap/cache"

    # Ensure storage subdirectories exist
    mkdir -p "${PELICAN_DIR}/storage/framework/"{cache/data,sessions,views}
    mkdir -p "${PELICAN_DIR}/storage/logs"
    chown -R "${WEBSERVER_USER}:${WEBSERVER_USER}" "${PELICAN_DIR}/storage"

    success "Permissions set (owner: ${WEBSERVER_USER}, storage: 775)"
}

create_admin_user() {
    if [[ -z "$ADMIN_EMAIL" || -z "$ADMIN_USER" || -z "$ADMIN_PASSWORD" ]]; then
        info "Admin user not specified — you'll create one via the web installer at /installer"
        return
    fi

    step "Creating admin user"

    cd "$PELICAN_DIR"

    # Use artisan tinker to create the admin user
    php artisan tinker --execute="
        \$user = new \App\Models\User();
        \$user->email = '${ADMIN_EMAIL}';
        \$user->username = '${ADMIN_USER}';
        \$user->password = bcrypt('${ADMIN_PASSWORD}');
        \$user->root_admin = true;
        \$user->save();
        echo 'Admin user created: ${ADMIN_EMAIL}';
    " >> "$LOG_FILE" 2>&1

    if [[ $? -eq 0 ]]; then
        success "Admin user created: ${ADMIN_EMAIL} (${ADMIN_USER})"

        # Mark as installed so /installer redirects to login
        set_env "APP_INSTALLED" "true"
        success "Panel marked as installed — /installer will redirect to dashboard"

        echo ""
        echo -e "  ${GREEN}${BOLD}┌─────────────────────────────────────────────────┐${RESET}"
        echo -e "  ${GREEN}${BOLD}│  ADMIN CREDENTIALS                               │${RESET}"
        echo -e "  ${GREEN}${BOLD}├─────────────────────────────────────────────────┤${RESET}"
        echo -e "  ${GREEN}${BOLD}│${RESET}  Email:    ${WHITE}${ADMIN_EMAIL}${RESET}"
        echo -e "  ${GREEN}${BOLD}│${RESET}  Username: ${WHITE}${ADMIN_USER}${RESET}"
        echo -e "  ${GREEN}${BOLD}│${RESET}  Password: ${WHITE}${ADMIN_PASSWORD}${RESET}"
        echo -e "  ${GREEN}${BOLD}└─────────────────────────────────────────────────┘${RESET}"
        echo ""
    else
        warn "Failed to create admin user — you can create one via the web installer at /installer"
    fi
}

setup_queue_worker() {
    info "Creating queue worker service..."

    cat > /etc/systemd/system/pelican-queue.service <<QSVC
# Pelican Queue Worker — auto-installed by pelican-installer

[Unit]
Description=Pelican Queue Worker
After=network.target

[Service]
User=${WEBSERVER_USER}
Group=${WEBSERVER_USER}
Restart=always
ExecStart=/usr/bin/php ${PELICAN_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
QSVC

    systemctl daemon-reload
    systemctl enable --now pelican-queue >> "$LOG_FILE" 2>&1
    success "Queue worker service created and running"
}

setup_cron_job() {
    info "Setting up scheduled task cron..."

    local cron_line="* * * * * php ${PELICAN_DIR}/artisan schedule:run >> /dev/null 2>&1"
    (crontab -u "${WEBSERVER_USER}" -l 2>/dev/null | grep -v "schedule:run"; echo "$cron_line") | crontab -u "${WEBSERVER_USER}" -
    success "Cron job configured (runs every minute)"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Wings Installation
# ═══════════════════════════════════════════════════════════════════════════════

install_wings() {
    step "Installing Docker"

    if command -v docker &>/dev/null; then
        success "Docker already installed"
    else
        run_cmd "Installing Docker CE (this may take a minute)" bash -c "curl -sSL https://get.docker.com/ | CHANNEL=stable sh >> '$LOG_FILE' 2>&1"
        systemctl enable --now docker >> "$LOG_FILE" 2>&1
        success "Docker CE installed and running"
    fi

    step "Installing Wings daemon"

    mkdir -p "$WINGS_DIR" /var/run/wings

    local wings_url="${PELICAN_WINGS_BASE}/wings_linux_${WINGS_ARCH}"
    run_cmd "Downloading Wings binary (${WINGS_ARCH})" curl -sSL -o "$WINGS_BIN" "$wings_url"
    chmod u+x "$WINGS_BIN"
    success "Wings binary installed to ${WINGS_BIN}"

    step "Setting up Wings systemd service"

    cat > /etc/systemd/system/wings.service <<WSVC
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
WSVC

    systemctl daemon-reload
    systemctl enable wings >> "$LOG_FILE" 2>&1
    success "Wings systemd service created and enabled"

    # Write Wings config.yml template if proxy is set up
    if [[ "$WINGS_PROXY" == true ]]; then
        info "Wings reverse proxy is configured — set api.ssl.enabled: false in config.yml"
        info "The reverse proxy terminates SSL, Wings listens on HTTP"
    fi

    echo ""
    echo -e "  ${YELLOW}${BOLD}Wings requires configuration from Panel:${RESET}"
    echo -e "    ${DIM}1. Go to Panel admin → Nodes → Create New${RESET}"
    echo -e "    ${DIM}2. Copy the configuration YAML from the Configuration tab${RESET}"
    echo -e "    ${DIM}3. Paste it into: ${WHITE}${WINGS_DIR}/config.yml${RESET}"
    if [[ "$WINGS_PROXY" == true ]]; then
        echo -e "    ${DIM}4. In config.yml, set ${WHITE}api.ssl.enabled: false${RESET}"
        echo -e "    ${DIM}5. Then start Wings: ${WHITE}sudo systemctl start wings${RESET}"
    else
        echo -e "    ${DIM}4. Then start Wings: ${WHITE}sudo systemctl start wings${RESET}"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Uninstall
# ═══════════════════════════════════════════════════════════════════════════════

uninstall() {
    echo ""
    echo -e "  ${RED}${BOLD}⚠  Uninstall Pelican${RESET}"
    echo ""
    echo -e "  ${CYAN}[1]${RESET} Uninstall Panel"
    echo -e "  ${CYAN}[2]${RESET} Uninstall Wings"
    echo -e "  ${CYAN}[3]${RESET} Uninstall Both"
    echo -e "  ${CYAN}[4]${RESET} Cancel"
    echo ""
    ask "Select option [1-4]:"
    read -r choice

    case "$choice" in
        1) uninstall_panel ;;
        2) uninstall_wings ;;
        3) uninstall_panel; uninstall_wings ;;
        4|*) info "Cancelled."; exit 0 ;;
    esac
}

uninstall_panel() {
    if ! confirm "Remove all panel files in ${PELICAN_DIR}? (y/N):" "N"; then
        info "Aborted."; return
    fi

    step "Uninstalling Pelican Panel"

    # ── Read DB credentials from .env before deleting files ──
    local env_file="${PELICAN_DIR}/.env"
    local db_driver="" db_host="" db_port="" db_name="" db_user="" db_pass=""
    if [[ -f "$env_file" ]]; then
        db_driver=$(grep -E "^DB_CONNECTION=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_host=$(grep -E "^DB_HOST=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_port=$(grep -E "^DB_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_name=$(grep -E "^DB_DATABASE=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_user=$(grep -E "^DB_USERNAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_pass=$(grep -E "^DB_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi

    # ── Drop database & user if we found credentials ──
    if [[ -n "$db_driver" && -n "$db_name" && "$db_name" != "sqlite" ]]; then
        echo ""
        echo -e "  ${YELLOW}Found database:${RESET} ${CYAN}${db_driver}${RESET} → ${BOLD}${db_name}${RESET} (user: ${db_user:-<none>})"
        if confirm "  Drop database '${db_name}' and user '${db_user}'? (y/N):" "N"; then
            case "$db_driver" in
                mysql|mariadb)
                    info "Dropping MySQL/MariaDB database and user..."
                    if command -v mysql &>/dev/null; then
                        mysql -u root <<-EOSQL 2>/dev/null && success "Database '${db_name}' dropped" || warn "Could not drop database (maybe already gone or root needs a password)"
DROP DATABASE IF EXISTS \`${db_name}\`;
EOSQL
                        if [[ -n "$db_user" && "$db_user" != "root" ]]; then
                            mysql -u root <<-EOSQL 2>/dev/null && success "User '${db_user}' dropped" || warn "Could not drop user"
DROP USER IF EXISTS '${db_user}'@'${db_host:-127.0.0.1}';
DROP USER IF EXISTS '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOSQL
                        fi
                    else
                        warn "mysql client not found — run manually: DROP DATABASE ${db_name}; DROP USER '${db_user}'@'localhost';"
                    fi
                    ;;
                pgsql|postgres|postgresql)
                    info "Dropping PostgreSQL database and user..."
                    if command -v psql &>/dev/null; then
                        sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"${db_name}\";" 2>/dev/null \
                            && success "Database '${db_name}' dropped" \
                            || warn "Could not drop database (maybe already gone)"
                        if [[ -n "$db_user" && "$db_user" != "postgres" ]]; then
                            sudo -u postgres psql -c "DROP USER IF EXISTS \"${db_user}\";" 2>/dev/null \
                                && success "User '${db_user}' dropped" \
                                || warn "Could not drop user (may own other objects)"
                        fi
                    else
                        warn "psql client not found — run manually: DROP DATABASE ${db_name}; DROP USER ${db_user};"
                    fi
                    ;;
                sqlite)
                    # SQLite DB is just a file inside PELICAN_DIR — gets deleted with the directory
                    info "SQLite database will be removed with panel files."
                    ;;
                *)
                    warn "Unknown DB driver '${db_driver}' — please clean up the database manually."
                    ;;
            esac
        else
            info "Skipping database cleanup."
        fi
    fi

    # ── Stop services ──
    systemctl stop pelican-queue 2>/dev/null || true
    systemctl disable pelican-queue 2>/dev/null || true
    rm -f /etc/systemd/system/pelican-queue.service

    # ── Remove web server configs ──
    rm -f /etc/nginx/sites-enabled/pelican.conf /etc/nginx/sites-available/pelican.conf 2>/dev/null || true
    rm -f /etc/apache2/sites-enabled/pelican.conf /etc/apache2/sites-available/pelican.conf 2>/dev/null || true
    rm -f /etc/httpd/conf.d/pelican.conf 2>/dev/null || true
    # Caddy — remove pelican block from Caddyfile if present
    if [[ -f /etc/caddy/Caddyfile ]]; then
        sed -i '/# Pelican Panel/,/^}/d' /etc/caddy/Caddyfile 2>/dev/null || true
    fi

    # ── Remove panel directory ──
    rm -rf "$PELICAN_DIR"
    systemctl daemon-reload

    # ── Restart web server ──
    systemctl restart nginx 2>/dev/null || systemctl restart apache2 2>/dev/null || \
        systemctl restart httpd 2>/dev/null || systemctl restart caddy 2>/dev/null || true

    success "Pelican Panel uninstalled"
}

uninstall_wings() {
    if ! confirm "Stop and remove Wings? (y/N):" "N"; then
        info "Aborted."; return
    fi

    step "Uninstalling Wings"

    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    rm -f /etc/systemd/system/wings.service
    rm -f "$WINGS_BIN"

    # ── Remove web server reverse proxy configs ──
    rm -f /etc/nginx/sites-enabled/wings.conf /etc/nginx/sites-available/wings.conf 2>/dev/null || true
    rm -f /etc/apache2/sites-enabled/wings.conf /etc/apache2/sites-available/wings.conf 2>/dev/null || true
    rm -f /etc/httpd/conf.d/wings.conf 2>/dev/null || true
    # Caddy — remove wings block from Caddyfile if present
    if [[ -f /etc/caddy/Caddyfile ]]; then
        sed -i '/# Wings Proxy/,/^}/d' /etc/caddy/Caddyfile 2>/dev/null || true
    fi

    systemctl daemon-reload

    # ── Restart web server ──
    systemctl restart nginx 2>/dev/null || systemctl restart apache2 2>/dev/null || \
        systemctl restart httpd 2>/dev/null || systemctl restart caddy 2>/dev/null || true

    if confirm "Also remove Wings config and data (${WINGS_DIR})? (y/N):" "N"; then
        rm -rf "$WINGS_DIR"
        info "Wings config directory removed."
    fi

    # ── Clean up Let's Encrypt certs if desired ──
    if confirm "Remove any Let's Encrypt certificates obtained for Wings? (y/N):" "N"; then
        local wings_domain=""
        if [[ -f "${WINGS_DIR}/config.yml" ]]; then
            wings_domain=$(grep -E "^\s+cert:" "${WINGS_DIR}/config.yml" 2>/dev/null | grep -oP '/etc/letsencrypt/live/\K[^/]+' | head -1)
        fi
        if [[ -n "$wings_domain" ]]; then
            certbot delete --cert-name "$wings_domain" --non-interactive 2>/dev/null \
                && success "Cert for ${wings_domain} removed" \
                || warn "Could not remove cert — run: certbot delete --cert-name ${wings_domain}"
        else
            info "No Wings domain cert found to remove."
        fi
    fi

    success "Wings uninstalled"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Update
# ═══════════════════════════════════════════════════════════════════════════════

update_panel() {
    step "Updating Pelican Panel"

    [[ ! -d "$PELICAN_DIR" ]] && fatal "Panel not found at ${PELICAN_DIR}"
    cd "$PELICAN_DIR"

    php artisan down >> "$LOG_FILE" 2>&1 || true
    info "Panel in maintenance mode"

    cp .env ".env.backup.$(date +%Y%m%d%H%M%S)"
    success "Backed up .env"

    run_cmd "Downloading latest Pelican Panel" bash -c "curl -sSL '$PELICAN_PANEL_URL' | tar -xzv >> '$LOG_FILE' 2>&1"

    run_cmd "Updating PHP dependencies" \
        env COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

    php artisan migrate --seed --force >> "$LOG_FILE" 2>&1
    success "Database migrations applied"

    php artisan optimize:clear >> "$LOG_FILE" 2>&1
    success "Caches cleared"

    # Re-detect webserver user
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        if systemctl is-active --quiet nginx; then WEBSERVER_USER="nginx"
        elif systemctl is-active --quiet httpd; then WEBSERVER_USER="apache"
        elif systemctl is-active --quiet caddy; then WEBSERVER_USER="caddy"
        else WEBSERVER_USER="nginx"; fi
    else
        WEBSERVER_USER="www-data"
    fi

    chown -R "${WEBSERVER_USER}:${WEBSERVER_USER}" "$PELICAN_DIR"
    chmod -R 775 "${PELICAN_DIR}/storage" "${PELICAN_DIR}/bootstrap/cache"

    systemctl restart pelican-queue >> "$LOG_FILE" 2>&1 || true
    php artisan queue:restart >> "$LOG_FILE" 2>&1 || true
    php artisan up >> "$LOG_FILE" 2>&1

    success "Panel updated and back online!"
}

update_wings() {
    step "Updating Wings"

    systemctl stop wings >> "$LOG_FILE" 2>&1 || true

    run_cmd "Downloading latest Wings binary" curl -sSL -o "$WINGS_BIN" "${PELICAN_WINGS_BASE}/wings_linux_${WINGS_ARCH}"
    chmod u+x "$WINGS_BIN"

    systemctl start wings >> "$LOG_FILE" 2>&1
    success "Wings updated and restarted!"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Health Checks
# ═══════════════════════════════════════════════════════════════════════════════

health_check() {
    step "Running post-install health checks"

    local passed=0
    local failed=0

    check_pass() { success "$1"; passed=$((passed + 1)); }
    check_fail() { error "$1"; failed=$((failed + 1)); }

    # PHP
    if php -v &>/dev/null; then
        check_pass "PHP $(php -v | head -1 | awk '{print $2}') is working"
    else
        check_fail "PHP is not working"
    fi

    # Web server
    if [[ "$INSTALL_PANEL" == true || "$WINGS_PROXY" == true ]]; then
        local ws_active=false
        for svc in nginx apache2 httpd caddy; do
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                check_pass "${svc^} is running"
                ws_active=true
                break
            fi
        done
        [[ "$ws_active" == false ]] && check_fail "No web server is running"
    fi

    if [[ "$INSTALL_PANEL" == true ]]; then
        # Panel files
        if [[ -f "${PELICAN_DIR}/artisan" ]]; then
            check_pass "Panel files present at ${PELICAN_DIR}"
        else
            check_fail "Panel files missing"
        fi

        # .env has APP_KEY
        if grep -q "^APP_KEY=base64:" "${PELICAN_DIR}/.env" 2>/dev/null; then
            check_pass ".env has APP_KEY"
        else
            check_fail ".env missing or no APP_KEY"
        fi

        # .env has DB_CONNECTION
        if grep -q "^DB_CONNECTION=" "${PELICAN_DIR}/.env" 2>/dev/null; then
            check_pass ".env has database config"
        else
            check_fail ".env missing database config"
        fi

        # .env has cache/session/queue config
        for setting in CACHE_STORE SESSION_DRIVER QUEUE_CONNECTION; do
            if grep -q "^${setting}=" "${PELICAN_DIR}/.env" 2>/dev/null; then
                check_pass ".env has ${setting}"
            else
                check_fail ".env missing ${setting}"
            fi
        done

        # Queue worker
        if systemctl is-active --quiet pelican-queue; then
            check_pass "Queue worker is running"
        else
            check_fail "Queue worker is not running"
        fi

        # Artisan CLI
        if cd "$PELICAN_DIR" && php artisan --version >> "$LOG_FILE" 2>&1; then
            check_pass "Artisan CLI works"
        else
            check_fail "Artisan CLI errors (check ${LOG_FILE})"
        fi

        # HTTP check
        if [[ -n "$FQDN" ]]; then
            local proto="http"
            [[ "$CONFIGURE_SSL" == true || "${WEBSERVER:-}" == "caddy" ]] && proto="https"
            local http_code
            http_code=$(curl -sSo /dev/null -w '%{http_code}' --max-time 10 "${proto}://${FQDN}" 2>/dev/null || echo "000")
            if [[ "$http_code" =~ ^(200|302|301)$ ]]; then
                check_pass "Panel responds at ${proto}://${FQDN} (HTTP ${http_code})"
            else
                check_fail "Panel not responding at ${proto}://${FQDN} (HTTP ${http_code})"
            fi
        fi

        # Database service
        if [[ "$DB_CHOICE" != "sqlite" ]]; then
            case "$DB_CHOICE" in
                mysql)   systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null && check_pass "MySQL is running" || check_fail "MySQL not running" ;;
                mariadb) systemctl is-active --quiet mariadb && check_pass "MariaDB is running" || check_fail "MariaDB not running" ;;
                postgres) systemctl is-active --quiet postgresql && check_pass "PostgreSQL is running" || check_fail "PostgreSQL not running" ;;
            esac
        fi

        # Redis (if used)
        if needs_redis; then
            if systemctl is-active --quiet redis-server 2>/dev/null || systemctl is-active --quiet redis 2>/dev/null; then
                check_pass "Redis is running"
            else
                check_fail "Redis not running"
            fi
        fi
    fi

    # Wings
    if [[ "$INSTALL_WINGS_FLAG" == true ]]; then
        [[ -x "$WINGS_BIN" ]] && check_pass "Wings binary installed" || check_fail "Wings binary missing"
        systemctl is-active --quiet docker && check_pass "Docker is running" || check_fail "Docker not running"
    fi

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}✓ All ${passed} checks passed!${RESET}"
    else
        echo -e "  ${YELLOW}${BOLD}⚠ ${passed} passed, ${failed} failed — review issues above${RESET}"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Interactive Menus
# ═══════════════════════════════════════════════════════════════════════════════

select_components() {
    echo ""
    echo -e "  ${BOLD}What would you like to install?${RESET}"
    echo ""
    echo -e "  ${CYAN}[1]${RESET} Panel only"
    echo -e "  ${CYAN}[2]${RESET} Wings only"
    echo -e "  ${CYAN}[3]${RESET} Panel + Wings ${DIM}(same machine)${RESET}"
    echo ""
    ask "Select [1-3]:"
    read -r comp
    case "${comp:-1}" in
        1) INSTALL_PANEL=true;  INSTALL_WINGS_FLAG=false ;;
        2) INSTALL_PANEL=false; INSTALL_WINGS_FLAG=true ;;
        3) INSTALL_PANEL=true;  INSTALL_WINGS_FLAG=true ;;
        *) INSTALL_PANEL=true;  INSTALL_WINGS_FLAG=false ;;
    esac
}

collect_panel_options() {
    echo ""
    echo -e "  ${BOLD}${WHITE}Panel Configuration${RESET}"
    echo -e "  ${DIM}$(printf '%.0s─' {1..40})${RESET}"

    # ── App Name ──
    if [[ "$ASSUME_YES" != true ]]; then
        echo ""
        ask "Application name [${APP_NAME}]:"
        read -r input_app_name
        APP_NAME="${input_app_name:-$APP_NAME}"
    fi

    # ── Domain ──
    if [[ -z "$FQDN" ]]; then
        echo ""
        ask "Panel domain (e.g., panel.example.com):"
        read -r FQDN
        [[ -z "$FQDN" ]] && fatal "Domain is required."
    fi

    # Validate FQDN
    if [[ ! "$FQDN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        warn "Domain '${FQDN}' looks unusual — double-check it's correct"
    fi

    # ── Web server ──
    if [[ -z "$WEBSERVER" ]]; then
        echo ""
        echo -e "  ${BOLD}Web server:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} Nginx ${DIM}(recommended)${RESET}"
        echo -e "  ${CYAN}[2]${RESET} Apache"
        echo -e "  ${CYAN}[3]${RESET} Caddy ${DIM}(automatic SSL, easiest setup)${RESET}"
        echo ""
        ask "Select [1-3] (default: 1):"
        read -r ws
        case "${ws:-1}" in
            1) WEBSERVER="nginx" ;;
            2) WEBSERVER="apache" ;;
            3) WEBSERVER="caddy" ;;
            *) WEBSERVER="nginx" ;;
        esac
    fi

    update_webserver_user

    # ── Database ──
    if [[ -z "$DB_CHOICE" ]]; then
        echo ""
        echo -e "  ${BOLD}Database:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} SQLite ${DIM}(simplest, no server needed)${RESET}"
        echo -e "  ${CYAN}[2]${RESET} MySQL"
        echo -e "  ${CYAN}[3]${RESET} MariaDB"
        echo -e "  ${CYAN}[4]${RESET} PostgreSQL ${DIM}(recommended for production)${RESET}"
        echo ""
        ask "Select [1-4] (default: 1):"
        read -r db
        case "${db:-1}" in
            1) DB_CHOICE="sqlite" ;;
            2) DB_CHOICE="mysql" ;;
            3) DB_CHOICE="mariadb" ;;
            4) DB_CHOICE="postgres" ;;
            *) DB_CHOICE="sqlite" ;;
        esac
    fi

    auto_set_db_port
    generate_db_password

    # Custom DB credentials (skip for sqlite)
    if [[ "$DB_CHOICE" != "sqlite" && "$ASSUME_YES" != true ]]; then
        echo ""
        ask "Database name [${DB_NAME}]:"
        read -r input_db_name
        DB_NAME="${input_db_name:-$DB_NAME}"

        ask "Database user [${DB_USER}]:"
        read -r input_db_user
        DB_USER="${input_db_user:-$DB_USER}"

        ask "Database password [auto-generated]:"
        read -r -s input_db_pass
        echo ""
        DB_PASSWORD="${input_db_pass:-$DB_PASSWORD}"
    fi

    # ── Cache ──
    if [[ -z "$CACHE_DRIVER" ]]; then
        echo ""
        echo -e "  ${BOLD}Cache driver:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} Filesystem ${DIM}(default, no extra setup)${RESET}"
        echo -e "  ${CYAN}[2]${RESET} Redis ${DIM}(faster, recommended for production)${RESET}"
        echo ""
        ask "Select [1-2] (default: 1):"
        read -r cache_choice
        case "${cache_choice:-1}" in
            1) CACHE_DRIVER="file" ;;
            2) CACHE_DRIVER="redis" ;;
            *) CACHE_DRIVER="file" ;;
        esac
    fi

    # Redis settings (if needed by any driver)
    if [[ "$CACHE_DRIVER" == "redis" && "$ASSUME_YES" != true ]]; then
        echo ""
        echo -e "  ${BOLD}Redis configuration:${RESET}"
        ask "Redis host [${REDIS_HOST}]:"
        read -r input_redis_host
        REDIS_HOST="${input_redis_host:-$REDIS_HOST}"

        ask "Redis port [${REDIS_PORT}]:"
        read -r input_redis_port
        REDIS_PORT="${input_redis_port:-$REDIS_PORT}"

        ask "Redis password [none]:"
        read -r -s input_redis_pass
        echo ""
        REDIS_PASSWORD="${input_redis_pass:-$REDIS_PASSWORD}"
    fi

    # ── Session ──
    if [[ -z "$SESSION_DRIVER" ]]; then
        echo ""
        echo -e "  ${BOLD}Session driver:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} Filesystem ${DIM}(default)${RESET}"
        echo -e "  ${CYAN}[2]${RESET} Database"
        echo -e "  ${CYAN}[3]${RESET} Cookie"
        if [[ "$CACHE_DRIVER" == "redis" ]]; then
            echo -e "  ${CYAN}[4]${RESET} Redis ${DIM}(fastest)${RESET}"
        fi
        echo ""
        local session_default=1
        ask "Select [1-$([[ "$CACHE_DRIVER" == "redis" ]] && echo "4" || echo "3")] (default: 1):"
        read -r session_choice
        case "${session_choice:-1}" in
            1) SESSION_DRIVER="file" ;;
            2) SESSION_DRIVER="database" ;;
            3) SESSION_DRIVER="cookie" ;;
            4) [[ "$CACHE_DRIVER" == "redis" ]] && SESSION_DRIVER="redis" || SESSION_DRIVER="file" ;;
            *) SESSION_DRIVER="file" ;;
        esac
    fi

    # ── Queue ──
    if [[ -z "$QUEUE_DRIVER" ]]; then
        echo ""
        echo -e "  ${BOLD}Queue driver:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} Database ${DIM}(default, reliable)${RESET}"
        if [[ "$CACHE_DRIVER" == "redis" ]]; then
            echo -e "  ${CYAN}[2]${RESET} Redis ${DIM}(faster)${RESET}"
        fi
        echo -e "  ${CYAN}[3]${RESET} Sync ${DIM}(immediate, for testing only)${RESET}"
        echo ""
        ask "Select [1-3] (default: 1):"
        read -r queue_choice
        case "${queue_choice:-1}" in
            1) QUEUE_DRIVER="database" ;;
            2) [[ "$CACHE_DRIVER" == "redis" ]] && QUEUE_DRIVER="redis" || QUEUE_DRIVER="database" ;;
            3) QUEUE_DRIVER="sync" ;;
            *) QUEUE_DRIVER="database" ;;
        esac
    fi

    # ── SSL ──
    if [[ -z "$CONFIGURE_SSL" ]]; then
        if [[ "$WEBSERVER" == "caddy" ]]; then
            CONFIGURE_SSL=false  # Caddy handles it
            info "Caddy handles SSL automatically"
        else
            echo ""
            if confirm "Enable SSL with Let's Encrypt? (Y/n):" "Y"; then
                CONFIGURE_SSL=true
                if [[ -z "$EMAIL" ]]; then
                    ask "Email for Let's Encrypt certificates:"
                    read -r EMAIL
                    [[ -z "$EMAIL" ]] && fatal "Email is required for SSL"
                fi
            else
                CONFIGURE_SSL=false
            fi
        fi
    fi

    # ── Admin user ──
    if [[ -z "$ADMIN_EMAIL" && "$ASSUME_YES" != true ]]; then
        echo ""
        echo -e "  ${BOLD}Admin account ${DIM}(optional — skip to use web installer)${RESET}"
        ask "Admin email (leave empty to skip):"
        read -r ADMIN_EMAIL
        if [[ -n "$ADMIN_EMAIL" ]]; then
            ask "Admin username:"
            read -r ADMIN_USER
            ask "Admin password:"
            read -r -s ADMIN_PASSWORD
            echo ""
        fi
    fi

    # ── Timezone ──
    if [[ "$ASSUME_YES" != true ]]; then
        echo ""
        ask "Timezone [${TIMEZONE}]:"
        read -r input_tz
        TIMEZONE="${input_tz:-$TIMEZONE}"
    fi
}

collect_wings_options() {
    if [[ "$ASSUME_YES" == true ]]; then
        return
    fi

    echo ""
    echo -e "  ${BOLD}${WHITE}Wings Configuration${RESET}"
    echo -e "  ${DIM}$(printf '%.0s─' {1..40})${RESET}"

    # Wings reverse proxy
    if [[ -z "$WINGS_PROXY" ]]; then
        echo ""
        if confirm "Set up a reverse proxy for Wings? (Y/n):" "Y"; then
            WINGS_PROXY=true
        else
            WINGS_PROXY=false
        fi
    fi

    if [[ "$WINGS_PROXY" == true ]]; then
        if [[ -z "$WINGS_DOMAIN" ]]; then
            ask "Wings node domain (e.g., node.example.com):"
            read -r WINGS_DOMAIN
            [[ -z "$WINGS_DOMAIN" ]] && { warn "No Wings domain specified — skipping proxy"; WINGS_PROXY=false; return; }
        fi

        ask "Wings daemon port [${WINGS_PORT}]:"
        read -r input_wings_port
        WINGS_PORT="${input_wings_port:-$WINGS_PORT}"

        if [[ -z "$WINGS_SSL" ]]; then
            if [[ "$WEBSERVER" == "caddy" ]]; then
                WINGS_SSL=false  # Caddy handles it
                info "Caddy handles Wings SSL automatically"
            elif [[ "$CONFIGURE_SSL" == true ]]; then
                if confirm "Enable SSL for Wings reverse proxy too? (Y/n):" "Y"; then
                    WINGS_SSL=true
                else
                    WINGS_SSL=false
                fi
            fi
        fi

        # Need a webserver choice for wings-only installs
        if [[ "$INSTALL_PANEL" != true && -z "$WEBSERVER" ]]; then
            echo ""
            echo -e "  ${BOLD}Web server for Wings reverse proxy:${RESET}"
            echo -e "  ${CYAN}[1]${RESET} Nginx ${DIM}(recommended)${RESET}"
            echo -e "  ${CYAN}[2]${RESET} Apache"
            echo -e "  ${CYAN}[3]${RESET} Caddy ${DIM}(automatic SSL)${RESET}"
            echo ""
            ask "Select [1-3] (default: 1):"
            read -r ws
            case "${ws:-1}" in
                1) WEBSERVER="nginx" ;;
                2) WEBSERVER="apache" ;;
                3) WEBSERVER="caddy" ;;
                *) WEBSERVER="nginx" ;;
            esac
        fi
    fi
}

show_summary() {
    echo ""
    echo -e "  ${CYAN}${BOLD}╔═══════════════════════════════════════════╗${RESET}"
    echo -e "  ${CYAN}${BOLD}║          Installation Summary              ║${RESET}"
    echo -e "  ${CYAN}${BOLD}╚═══════════════════════════════════════════╝${RESET}"
    echo ""

    if [[ "$INSTALL_PANEL" == true ]]; then
        echo -e "  ${BOLD}Panel:${RESET}"
        echo -e "    App name:     ${GREEN}${APP_NAME}${RESET}"
        echo -e "    Domain:       ${GREEN}${FQDN}${RESET}"
        echo -e "    Web server:   ${GREEN}${WEBSERVER}${RESET}"
        echo -e "    Database:     ${GREEN}${DB_CHOICE}${RESET}"
        if [[ "$DB_CHOICE" != "sqlite" ]]; then
            echo -e "    DB name:      ${GREEN}${DB_NAME}${RESET}"
            echo -e "    DB user:      ${GREEN}${DB_USER}${RESET}"
        fi
        echo -e "    Cache:        ${GREEN}${CACHE_DRIVER}${RESET}"
        echo -e "    Session:      ${GREEN}${SESSION_DRIVER}${RESET}"
        echo -e "    Queue:        ${GREEN}${QUEUE_DRIVER}${RESET}"
        echo -e "    SSL:          ${GREEN}$([[ "$CONFIGURE_SSL" == true || "$WEBSERVER" == "caddy" ]] && echo "Yes" || echo "No")${RESET}"
        echo -e "    Timezone:     ${GREEN}${TIMEZONE}${RESET}"
        echo -e "    PHP:          ${GREEN}${PHP_VERSION}${RESET}"
        if [[ -n "$ADMIN_EMAIL" ]]; then
            echo -e "    Admin:        ${GREEN}${ADMIN_EMAIL} (${ADMIN_USER})${RESET}"
        else
            echo -e "    Admin:        ${DIM}via web installer${RESET}"
        fi
        echo ""
    fi

    if [[ "$INSTALL_WINGS_FLAG" == true ]]; then
        echo -e "  ${BOLD}Wings:${RESET}"
        echo -e "    Architecture: ${GREEN}${WINGS_ARCH}${RESET}"
        echo -e "    Docker:       ${GREEN}Will be installed${RESET}"
        if [[ "$WINGS_PROXY" == true ]]; then
            echo -e "    Proxy:        ${GREEN}${WEBSERVER} → ${WINGS_DOMAIN}:${WINGS_PORT}${RESET}"
            echo -e "    Proxy SSL:    ${GREEN}$([[ "$WINGS_SSL" == true || "$WEBSERVER" == "caddy" ]] && echo "Yes" || echo "No")${RESET}"
        else
            echo -e "    Proxy:        ${DIM}Not configured${RESET}"
        fi
        echo ""
    fi

    if ! confirm "Proceed with installation? (Y/n):" "Y"; then
        info "Installation cancelled."
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Completion Messages
# ═══════════════════════════════════════════════════════════════════════════════

print_complete() {
    local proto="http"
    [[ "$CONFIGURE_SSL" == true || "$WEBSERVER" == "caddy" ]] && proto="https"

    echo ""
    echo -e "  ${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                           ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║     🎉  Installation completed successfully!  🎉          ║${RESET}"
    echo -e "  ${GREEN}${BOLD}║                                                           ║${RESET}"
    echo -e "  ${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    if [[ "$INSTALL_PANEL" == true ]]; then
        echo -e "  ${BOLD}Panel — next steps:${RESET}"
        if [[ -n "$ADMIN_EMAIL" ]]; then
            echo -e "    ${WHITE}1.${RESET} Open ${CYAN}${proto}://${FQDN}${RESET} and log in"
            echo -e "       Email:    ${WHITE}${ADMIN_EMAIL}${RESET}"
            echo -e "       Username: ${WHITE}${ADMIN_USER}${RESET}"
        else
            echo -e "    ${WHITE}1.${RESET} Open ${CYAN}${proto}://${FQDN}/installer${RESET} in your browser"
            echo -e "    ${WHITE}2.${RESET} Complete the web-based setup wizard"
            echo -e "       ${DIM}(Database, cache, session, and queue are already configured!)${RESET}"
            echo -e "    ${WHITE}3.${RESET} Create your admin account"
        fi
        echo ""
    fi

    if [[ "$INSTALL_WINGS_FLAG" == true ]]; then
        echo -e "  ${BOLD}Wings — next steps:${RESET}"
        echo -e "    ${WHITE}1.${RESET} Create a node in Panel admin → Nodes → Create New"
        if [[ "$WINGS_PROXY" == true ]]; then
            local wings_proto="http"
            [[ "$WINGS_SSL" == true || "$WEBSERVER" == "caddy" ]] && wings_proto="https"
            echo -e "       Use FQDN: ${CYAN}${WINGS_DOMAIN}${RESET}"
            echo -e "       Set 'Communicate Over SSL' to ${CYAN}$([[ "$wings_proto" == "https" ]] && echo "Use SSL" || echo "No SSL")${RESET}"
            echo -e "       Set 'Behind Proxy' to ${CYAN}Behind Proxy${RESET}"
        fi
        echo -e "    ${WHITE}2.${RESET} Copy the config YAML into ${CYAN}${WINGS_DIR}/config.yml${RESET}"
        if [[ "$WINGS_PROXY" == true ]]; then
            echo -e "    ${WHITE}3.${RESET} In config.yml, ensure: ${CYAN}api.ssl.enabled: false${RESET}"
            echo -e "       ${DIM}(The reverse proxy terminates SSL — Wings listens on plain HTTP)${RESET}"
            echo -e "    ${WHITE}4.${RESET} Test: ${CYAN}sudo wings --debug${RESET}"
            echo -e "    ${WHITE}5.${RESET} Start: ${CYAN}sudo systemctl start wings${RESET}"
        else
            echo -e "    ${WHITE}3.${RESET} Test: ${CYAN}sudo wings --debug${RESET}"
            echo -e "    ${WHITE}4.${RESET} Start: ${CYAN}sudo systemctl start wings${RESET}"
        fi
        echo ""
    fi

    echo -e "  ${BOLD}Useful commands:${RESET}"
    echo -e "    Update:     ${CYAN}sudo bash install.sh update --both${RESET}"
    echo -e "    Uninstall:  ${CYAN}sudo bash install.sh uninstall${RESET}"
    echo -e "    Logs:       ${CYAN}tail -f ${LOG_FILE}${RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"

    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Pelican Installer v${INSTALLER_VERSION} — $(date) ===" >> "$LOG_FILE"

    print_header
    detect_os
    preflight_checks

    # Determine action
    if [[ -z "$ACTION" ]]; then
        echo ""
        echo -e "  ${BOLD}What would you like to do?${RESET}"
        echo ""
        echo -e "  ${CYAN}[1]${RESET} Install Panel / Wings"
        echo -e "  ${CYAN}[2]${RESET} Update Panel / Wings"
        echo -e "  ${CYAN}[3]${RESET} Uninstall"
        echo ""
        ask "Select [1-3] (default: 1):"
        read -r action_choice
        case "${action_choice:-1}" in
            1) ACTION="install" ;;
            2) ACTION="update" ;;
            3) ACTION="uninstall" ;;
            *) ACTION="install" ;;
        esac
    fi

    case "$ACTION" in
        install)
            # If components not set via flags, ask
            if [[ -z "$INSTALL_PANEL" && -z "$INSTALL_WINGS_FLAG" ]]; then
                select_components
            fi
            INSTALL_PANEL="${INSTALL_PANEL:-false}"
            INSTALL_WINGS_FLAG="${INSTALL_WINGS_FLAG:-false}"

            # Calculate total steps for progress indicator
            TOTAL_STEPS=2  # detect + preflight (already done)
            CURRENT_STEP=2
            if [[ "$INSTALL_PANEL" == true ]]; then
                TOTAL_STEPS=$((TOTAL_STEPS + 7))  # php, redis?, db, webserver, ssl, panel-download, panel-config
            fi
            if [[ "$INSTALL_WINGS_FLAG" == true ]]; then
                TOTAL_STEPS=$((TOTAL_STEPS + 3))  # docker, wings-download, wings-service
                if [[ "$WINGS_PROXY" == true && "$INSTALL_PANEL" != true ]]; then
                    TOTAL_STEPS=$((TOTAL_STEPS + 1))  # webserver for wings only
                fi
            fi
            TOTAL_STEPS=$((TOTAL_STEPS + 1))  # health check

            if [[ "$INSTALL_PANEL" == true ]]; then
                detect_php_version
                collect_panel_options
            fi

            if [[ "$INSTALL_WINGS_FLAG" == true ]]; then
                collect_wings_options
            fi

            show_summary

            if [[ "$INSTALL_PANEL" == true ]]; then
                install_php
                install_redis
                install_database
                install_webserver
                install_ssl
                install_panel
            elif [[ "$WINGS_PROXY" == true ]]; then
                # Wings-only with reverse proxy needs a web server
                install_webserver
                install_ssl
            fi

            if [[ "$INSTALL_WINGS_FLAG" == true ]]; then
                install_wings
            fi

            health_check
            print_complete
            ;;

        update)
            if [[ -z "$INSTALL_PANEL" && -z "$INSTALL_WINGS_FLAG" ]]; then
                echo ""
                echo -e "  ${BOLD}What would you like to update?${RESET}"
                echo ""
                echo -e "  ${CYAN}[1]${RESET} Panel"
                echo -e "  ${CYAN}[2]${RESET} Wings"
                echo -e "  ${CYAN}[3]${RESET} Both"
                echo ""
                ask "Select [1-3]:"
                read -r upd
                case "${upd:-1}" in
                    1) INSTALL_PANEL=true;  INSTALL_WINGS_FLAG=false ;;
                    2) INSTALL_PANEL=false; INSTALL_WINGS_FLAG=true ;;
                    3) INSTALL_PANEL=true;  INSTALL_WINGS_FLAG=true ;;
                    *) INSTALL_PANEL=true;  INSTALL_WINGS_FLAG=false ;;
                esac
            fi

            detect_php_version
            [[ "$INSTALL_PANEL" == true ]]      && update_panel
            [[ "$INSTALL_WINGS_FLAG" == true ]]  && update_wings

            echo ""
            echo -e "  ${GREEN}${BOLD}✓ Update complete!${RESET}"
            echo ""
            ;;

        uninstall)
            uninstall
            ;;

        *)
            fatal "Unknown action: ${ACTION}"
            ;;
    esac

    log "Installer finished at $(date)"
}

# ─── Run ───────────────────────────────────────────────────────────────────────
main "$@"
