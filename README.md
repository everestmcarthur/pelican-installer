# 🐦 Pelican Installer

The best way to install [Pelican Panel](https://pelican.dev) & Wings — one script, fully automated, production-ready.

## Quick Start

```bash
# Interactive install (asks you everything)
sudo bash <(curl -sSL https://raw.githubusercontent.com/everestmcarthur/pelican-installer/main/install.sh)

# Or download first
curl -sSL -o install.sh https://raw.githubusercontent.com/everestmcarthur/pelican-installer/main/install.sh
sudo bash install.sh
```

## Automated Install (No Prompts)

```bash
# Panel with Nginx + PostgreSQL + SSL
sudo bash install.sh install --panel \
    --domain panel.example.com \
    --webserver nginx \
    --database postgres \
    --ssl --email admin@example.com \
    --timezone America/New_York \
    -y

# Wings only
sudo bash install.sh install --wings -y

# Panel + Wings on same machine
sudo bash install.sh install --both \
    --domain panel.example.com \
    --webserver caddy \
    --database postgres \
    -y
```

## All CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `install` / `update` / `uninstall` | Action to perform | `install` |
| `--panel` | Install/update Panel | — |
| `--wings` | Install/update Wings | — |
| `--both` | Install/update Panel + Wings | — |
| `--domain FQDN` | Panel domain name | *(asked)* |
| `--webserver WS` | `nginx`, `apache`, or `caddy` | *(asked)* |
| `--database DB` | `sqlite`, `mysql`, `mariadb`, or `postgres` | *(asked)* |
| `--db-host HOST` | Database host | `127.0.0.1` |
| `--db-port PORT` | Database port | *auto from DB type* |
| `--db-name NAME` | Database name | `pelican` |
| `--db-user USER` | Database user | `pelican` |
| `--db-password PASS` | Database password | *auto-generated* |
| `--ssl` | Enable SSL via Let's Encrypt | *(asked)* |
| `--no-ssl` | Disable SSL | — |
| `--email EMAIL` | Email for Let's Encrypt | *(asked if --ssl)* |
| `--timezone TZ` | Server timezone | `UTC` |
| `--yes`, `-y` | Skip all confirmation prompts | `false` |

## Environment Variables

Every flag can also be set via environment variable:

```bash
export FQDN="panel.example.com"
export WEBSERVER="nginx"
export DB_CHOICE="postgres"
export DB_PASSWORD="my_secure_password"
export CONFIGURE_SSL=true
export EMAIL="admin@example.com"
export ASSUME_YES=true
sudo -E bash install.sh install --panel
```

## Features

| Feature | This Installer | pterodactyl-installer.se |
|---------|:-:|:-:|
| Pelican Panel support | ✅ | ❌ (Pterodactyl only) |
| Full CLI flags (automated installs) | ✅ | ❌ |
| Environment variable config | ✅ | ❌ |
| Nginx | ✅ | ✅ |
| Apache | ✅ | ✅ |
| Caddy (auto-SSL) | ✅ | ❌ |
| SQLite | ✅ | ❌ |
| MySQL | ✅ | ✅ |
| MariaDB | ✅ | ✅ |
| PostgreSQL | ✅ | ❌ |
| Auto-configures `.env` | ✅ | ❌ |
| Runs database migrations | ✅ | ❌ |
| PostgreSQL `pg_hba.conf` auth | ✅ | ❌ |
| Writes DB password to `.env` | ✅ | ❌ |
| Let's Encrypt SSL | ✅ | ✅ |
| Post-install health checks | ✅ | ❌ |
| HTTP connectivity check | ✅ | ❌ |
| Queue worker systemd service | ✅ | ❌ |
| Cron auto-setup | ✅ | ❌ |
| Step-by-step progress (X/Y) | ✅ | ❌ |
| Update command | ✅ | ❌ |
| Uninstall command | ✅ | ❌ |
| ARM64 support | ✅ | ❌ |
| Comprehensive logging | ✅ | ❌ |
| Single script (no deps) | ✅ | ✅ |

## Update & Uninstall

```bash
# Update panel
sudo bash install.sh update --panel

# Update wings
sudo bash install.sh update --wings

# Update both
sudo bash install.sh update --both -y

# Uninstall (interactive)
sudo bash install.sh uninstall
```

## Supported Systems

| OS | Versions |
|----|----------|
| Ubuntu | 22.04, 24.04 |
| Debian | 11, 12 |
| AlmaLinux | 8, 9 |
| Rocky Linux | 8, 9 |
| CentOS Stream | 9 |

Both `x86_64` and `ARM64` architectures supported.

## Logs

All installer output is logged to `/var/log/pelican-installer.log`.

```bash
tail -f /var/log/pelican-installer.log
```

## License

GPL-3.0 — See [LICENSE](LICENSE)
