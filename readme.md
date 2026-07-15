# SSTP Manager - Web-Based SSTP VPN Management

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://www.linux.org/)

A web-based management interface for SSTP VPN servers with per-user routing. Manage VPN users, routes, and service status through a Bootstrap 5 dashboard. Designed for MikroTik SSTP client compatibility.

## Key Features

- **Secure Web Interface** - HTTPS dashboard with session management and CSRF protection
- **User Management** - Add, edit, delete SSTP users with static IP assignment
- **Per-User Routing** - Assign custom routes to individual VPN users
- **One-Click Installation** - Deploy everything with a single command
- **MikroTik Compatible** - Includes RSA cipher suite for RouterOS 6.x/7.x support
- **Responsive Design** - Bootstrap 5 UI, works on desktop and mobile

## Quick Start

Install SSTP server, web panel, and per-user routing in one command:

```bash
curl -sL https://raw.githubusercontent.com/bakhtyarjaff98/sstp-manager/master/all-in-one-installer.sh | sudo bash
```

## Manual Installation Options

### Full SSTP Server + Web Panel

```bash
curl -sL https://raw.githubusercontent.com/bakhtyarjaff98/sstp-manager/master/sas4-sstp-full-installer.sh | sudo bash
```

### Web Panel Only

Install only the web management interface (requires an existing SSTP server):

```bash
curl -sL https://raw.githubusercontent.com/bakhtyarjaff98/sstp-manager/master/sas4-install.sh | sudo bash
```

### Per-User Routing System

Add per-user routing capabilities:

```bash
curl -sL https://raw.githubusercontent.com/bakhtyarjaff98/sstp-manager/master/install-sstp-per-user-routing.sh | sudo bash
```

## Access Your Dashboard

After installation:

- **HTTP**:  `http://your-server-ip:8090/sstp-manager/`
- **HTTPS**: `https://your-server-ip:8099/sstp-manager/`

### Default Credentials
- **Username**: `admin`
- **Password**: `change@me` (change this immediately)

## Per-User Routing

Configure custom network routes that are applied when SSTP users connect.

### How It Works
1. Add routes through the web interface
2. Routes are stored in `/etc/sstp-manager/routes.d/`
3. When users connect, routes are applied to their PPP interface
4. When users disconnect, routes are cleaned up

## IP Addressing

| Network | Purpose |
|---------|---------|
| `10.200.0.0/16` | SSTP client pool |
| `10.200.10.1` | SSTP gateway (server side) |
| `10.200.10.11-254` | Default user IP range |

## System Requirements

- **OS**: Ubuntu/Debian-based Linux
- **Memory**: 512MB RAM minimum
- **Disk**: 100MB free space
- **Network**: Internet access for installation
- **Privileges**: Root/sudo access

## Troubleshooting

### Useful Commands

```bash
# Check SSTP service status
sudo systemctl status sstpd

# Check if sstpd is listening
ss -tlnp | grep 4433

# View SSTP server logs
sudo journalctl -u sstpd -f

# Check certificate expiry
openssl x509 -in /root/cert.pem -noout -dates

# List configured user routes
sudo /usr/local/sbin/sstp-routectl list
```

### Common Issues

| Issue | Fix |
|-------|-----|
| MikroTik "internal error (6)" | Ensure `--ciphers` parameter is set in sstpd.service |
| sstpd crash loop "host bits set" | Use `--remote 10.200.0.0/16` (not `10.200.10.0/16`) |
| Cannot access dashboard | Check Apache: `systemctl status apache2` |
| Route permission errors | Check `/etc/ppp/chap-secrets` is `root:www-data 660` |

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues or contributions, please [open an issue](https://github.com/bakhtyarjaff98/sstp-manager/issues) on GitHub.
