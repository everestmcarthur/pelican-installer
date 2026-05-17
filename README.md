# 🐦 Pelican Installer

The **best** way to install [Pelican Panel](https://pelican.dev) & Wings — a single command, beautiful UI, and way more features than the old Pterodactyl installer.

```bash
bash <(curl -s https://raw.githubusercontent.com/rosillathequeen/pelican-installer/main/install.sh)
```

## ✨ Features

| Feature | Pterodactyl Installer | Pelican Installer |
|---|---|---|
| Single-command install | ✅ | ✅ |
| Panel installation | ✅ | ✅ |
| Wings installation | ✅ | ✅ |
| Nginx support | ✅ | ✅ |
| Apache support | ✅ | ✅ |
| **Caddy support (auto-SSL)** | ❌ | ✅ |
| **SQLite support** | ❌ | ✅ |
| **PostgreSQL support** | ❌ | ✅ |
| MySQL/MariaDB support | ✅ | ✅ |
| Let's Encrypt SSL | ✅ | ✅ |
| **Beautiful colored UI** | ❌ | ✅ |
| **Progress spinners** | ❌ | ✅ |
| **Post-install health checks** | ❌ | ✅ |
| **Update command** | ❌ | ✅ |
| **Uninstall command** | ❌ | ✅ |
| **Memory & disk checks** | ❌ | ✅ |
| **Virtualization detection** | ❌ | ✅ |
| **Comprehensive logging** | Partial | ✅ |
| **Single script (no lib downloads)** | ❌ | ✅ |
| **Queue worker auto-setup** | ❌ | ✅ |
| **Cron job auto-setup** | ❌ | ✅ |
| ARM64 support | ❌ | ✅ |

## 📋 Supported Operating Systems

| OS | Version | Panel | Wings |
|---|---|---|---|
| Ubuntu | 22.04, 24.04 | ✅ | ✅ |
| Debian | 11, 12 | ✅ | ✅ |
| AlmaLinux | 8, 9, 10 | ✅ | ✅ |
| Rocky Linux | 8, 9 | ✅ | ✅ |
| CentOS | 10 | ✅ | ✅ |

## 🚀 Quick Start

### Install Panel
```bash
bash <(curl -s https://raw.githubusercontent.com/rosillathequeen/pelican-installer/main/install.sh)
# Select option [0] — Install Panel
```

### Install Wings
```bash
bash <(curl -s https://raw.githubusercontent.com/rosillathequeen/pelican-installer/main/install.sh)
# Select option [1] — Install Wings
```

### Install Both (same machine)
```bash
bash <(curl -s https://raw.githubusercontent.com/rosillathequeen/pelican-installer/main/install.sh)
# Select option [2] — Install Panel + Wings
```

### Update
```bash
bash <(curl -s https://raw.githubusercontent.com/rosillathequeen/pelican-installer/main/install.sh)
# Select option [3/4/5] — Update Panel/Wings/Both
```

### Uninstall
```bash
bash <(curl -s https://raw.githubusercontent.com/rosillathequeen/pelican-installer/main/install.sh)
# Select option [6] — Uninstall
```

## 🛠 What It Does

### Panel Installation
1. Detects your OS and installs the right packages
2. Installs PHP 8.5/8.4/8.3 with all required extensions
3. Installs your chosen database (SQLite, MySQL, MariaDB, or PostgreSQL)
4. Installs and configures your web server (Nginx, Apache, or Caddy)
5. Obtains SSL certificate via Let's Encrypt (or auto-SSL with Caddy)
6. Downloads and configures Pelican Panel
7. Sets up the queue worker as a systemd service
8. Configures the cron scheduler
9. Runs health checks to verify everything works

### Wings Installation
1. Installs Docker CE
2. Downloads the Wings binary (auto-detects amd64/arm64)
3. Creates the systemd service for Wings
4. Guides you through connecting to your Panel

## 📝 Logs

All installer output is logged to `/var/log/pelican-installer.log` for troubleshooting.

## 🔄 Auto-Update Monitoring

This repository is automatically monitored for new Pelican releases. When a new version drops, the installer is tested and updated.

## 📜 License

GPL-3.0 — Free and open source.

## 🙏 Credits

- [Pelican Panel](https://pelican.dev) — The game server management panel
- Inspired by [pterodactyl-installer](https://pterodactyl-installer.se)
