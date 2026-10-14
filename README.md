# ⚠️ ARCHIVED REPOSITORY — NO LONGER IN DEVELOPMENT

> [!WARNING]
> **THIS REPOSITORY HAS BEEN OFFICIALLY ARCHIVED AND IS NO LONGER IN ACTIVE DEVELOPMENT ON GITHUB.**
> 
> All code in this repository is preserved for historical reference only. No further updates, issues, or pull requests will be accepted or maintained here.

---

# 🐦 Pelican Installer

The best way to install [Pelican Panel](https://pelican.dev) & Wings — one command, fully automated.

> Better than the pterodactyl-installer. Every option configurable via CLI flags, full web server configs, Redis support, auto admin creation, and more.

## Quick Install

```bash
curl -sSL https://install.jarviscli.dev | sudo bash
```

Or directly from GitHub:

```bash
curl -sSL https://raw.githubusercontent.com/everestmcarthur/pelican-installer/main/install.sh | sudo bash
```

## Fully Automated Install (Non-Interactive)

```bash
curl -sSL https://install.jarviscli.dev | sudo bash -s -- install \
  --panel \
  --domain panel.example.com \
  --webserver nginx \
  --database postgres \
  --ssl --email you@example.com \
  --cache-driver redis \
  --session-driver redis \
  --queue-driver redis \
  --admin-email admin@example.com \
  --admin-user admin \
  --admin-pass S3cureP@ss \
  --timezone America/New_York \
  -y
```

## Panel + Wings (Same Machine)

```bash
curl -sSL https://install.jarviscli.dev | sudo bash -s -- install \
  --both \
  --domain panel.example.com \
  --wings-domain node.example.com \
  --wings-proxy --wings-ssl \
  --webserver nginx \
  --database postgres \
  --ssl --email you@example.com \
  -y
```

## Wings Only (With Reverse Proxy)

```bash
curl -sSL https://install.jarviscli.dev | sudo bash -s -- install \
  --wings \
  --wings-domain node.example.com \
  --wings-proxy \
  --webserver caddy \
  -y
```

## Update & Uninstall

```bash
# Update everything
sudo bash install.sh update --both -y

# Uninstall
sudo bash install.sh uninstall
```

## All CLI Flags

### Components
| Flag | Description |
|------|-------------|
| `--panel` | Install Panel |
| `--wings` | Install Wings |
| `--both` | Install Panel + Wings |

### Panel — General
| Flag | Description | Default |
|------|-------------|---------|
| `--domain FQDN` | Panel domain name | *(required)* |
| `--app-name NAME` | Application name | `Pelican` |
| `--webserver WS` | `nginx`, `apache`, or `caddy` | *(asked)* |
| `--ssl` | Enable SSL via Let's Encrypt | *(asked)* |
| `--no-ssl` | Disable SSL | |
| `--email EMAIL` | Let's Encrypt email | *(asked if SSL)* |
| `--timezone TZ` | Timezone | `UTC` |

### Panel — Admin User (Skip Web Installer)
| Flag | Description |
|------|-------------|
| `--admin-email EMAIL` | Admin email |
| `--admin-user USER` | Admin username |
| `--admin-pass PASS` | Admin password |

> If all three are provided, the admin user is created automatically and the web installer is skipped entirely.

### Panel — Database
| Flag | Description | Default |
|------|-------------|---------|
| `--database DB` | `sqlite`, `mysql`, `mariadb`, `postgres` | *(asked)* |
| `--db-host HOST` | Database host | `127.0.0.1` |
| `--db-port PORT` | Database port | *auto-detected* |
| `--db-name NAME` | Database name | `pelican` |
| `--db-user USER` | Database user | `pelican` |
| `--db-password PASS` | Database password | *auto-generated* |

### Panel — Cache
| Flag | Description | Default |
|------|-------------|---------|
| `--cache-driver DRV` | `file` or `redis` | `file` |
| `--redis-host HOST` | Redis host | `127.0.0.1` |
| `--redis-port PORT` | Redis port | `6379` |
| `--redis-user USER` | Redis username (ACL) | |
| `--redis-password PW` | Redis password | |

> When using Redis + localhost, Redis server is auto-installed.

### Panel — Session
| Flag | Description | Default |
|------|-------------|---------|
| `--session-driver DRV` | `file`, `database`, `cookie`, `redis` | `file` |

### Panel — Queue
| Flag | Description | Default |
|------|-------------|---------|
| `--queue-driver DRV` | `database`, `redis`, `sync` | `database` |

### Wings
| Flag | Description | Default |
|------|-------------|---------|
| `--wings-domain FQDN` | Wings node domain | |
| `--wings-port PORT` | Wings daemon port | `8080` |
| `--wings-proxy` | Set up reverse proxy | |
| `--wings-ssl` | SSL for Wings proxy | |

### General
| Flag | Description |
|------|-------------|
| `--yes`, `-y` | Skip all confirmation prompts |
| `--help`, `-h` | Show help |

## Features

- **Interactive & Non-Interactive** — Full wizard for beginners, CLI flags for automation
- **3 Web Servers** — Nginx, Apache, Caddy (with auto-SSL)
- **4 Databases** — SQLite, MySQL, MariaDB, PostgreSQL
- **Redis Everything** — Cache, session, and queue with auto-install
- **Wings Reverse Proxy** — Full config with WebSocket support for console/file manager on all 3 web servers
- **Auto Admin User** — Skip the web installer entirely
- **SSL Everywhere** — Let's Encrypt for Panel + Wings in one pass
- **Health Checks** — Verifies PHP, web server, database, Redis, .env, HTTP response
- **Update & Uninstall** — Built-in commands for lifecycle management
- **ARM64 Support** — Works on x86_64 and ARM machines
- **Progress Indicators** — Step counter, spinners, color-coded output
- **Credential Boxes** — Database password, APP_KEY, admin creds displayed clearly
- **Comprehensive Logging** — Everything logged to `/var/log/pelican-installer.log`

## Supported Operating Systems

- Ubuntu 20.04, 22.04, 24.04
- Debian 11, 12
- AlmaLinux 8, 9
- Rocky Linux 8, 9
- CentOS Stream 8, 9
- RHEL 8, 9

## What It Does

### Panel Install
1. Detects OS and architecture
2. Runs preflight checks (root, memory, disk, tools)
3. Installs PHP 8.2/8.3/8.4 with all required extensions
4. Installs Redis (if selected for cache/session/queue)
5. Installs and configures your chosen database
6. Installs and configures your chosen web server
7. Obtains SSL certificates (if enabled)
8. Downloads Pelican Panel + Composer dependencies
9. Writes full `.env` configuration (no web installer needed)
10. Runs database migrations and seeders
11. Creates admin user (if credentials provided)
12. Sets up queue worker systemd service
13. Configures cron job for scheduled tasks
14. Runs health checks

### Wings Install
1. Installs Docker CE
2. Downloads Wings binary for your architecture
3. Creates systemd service
4. Configures reverse proxy (if selected)

## License

GPL-3.0 — see [LICENSE](LICENSE).

## Credits

Built for [JarvisCLI](https://jarviscli.dev) by the Pelican Installer team.

Pelican Panel is created by [pelican-dev](https://github.com/pelican-dev) and is licensed under AGPL-3.0.
