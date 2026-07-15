#!/bin/bash

# ==============================================================================
# SAS4 SSTP Server - Full Installation Script
# ==============================================================================
# Installs a complete SSTP VPN server using sstp-server (Python) with:
#   - uv-managed Python 3.12 in an isolated venv
#   - Self-signed SSL certificate
#   - PPP authentication via chap-secrets
#   - systemd service with MikroTik-compatible cipher suite
#   - Firewall rules (NAT + port opening)
#   - SAS4 web management panel
#
# Lessons from manual setup on 82.196.13.143 are baked in — see comments.
# ==============================================================================

set -euo pipefail

# Report the line that failed instead of dying silently.
trap 'echo -e "${RED}Installation FAILED at line $LINENO. The server may be half-configured — re-run this script after fixing the error above.${NC}" >&2' ERR

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Require root
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    echo -e "${RED}This script needs root. Run with: sudo $0${NC}" >&2
    exit 1
fi

# Artwork
echo -e "${CYAN}"
echo " █████╗ ██████╗  █████╗ ███╗   ██╗ ██████╗ ██╗   ██╗██████╗ "
echo "██╔══██╗██╔══██╗██╔══██╗████╗  ██║██╔═══██╗██║   ██║██╔══██╗"
echo "███████║██████╔╝███████║██╔██╗ ██║██║   ██║██║   ██║██████╔╝"
echo "██╔══██║██╔══██╗██╔══██║██║╚██╗██║██║   ██║██║   ██║██╔══██╗"
echo "██║  ██║██████╔╝██║  ██║██║ ╚████║╚██████╔╝╚██████╔╝██████╔╝"
echo "╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ ╚═════╝ "
echo "                                                    "
echo " █████╗  ██████╗ ███╗   ██╗██████╗  ██████╗ ██╗   ██╗"
echo "██╔══██╗██╔═══██╗████╗  ██║██╔══██╗██╔═══██╗╚██╗ ██╔╝"
echo "███████║██║   ██║██╔██╗ ██║██████╔╝██║   ██║ ╚████╔╝ "
echo "██╔══██║██║   ██║██║╚██╗██║██╔══██╗██║   ██║  ╚██╔╝  "
echo "██║  ██║╚██████╔╝██║ ╚████║██████╔╝╚██████╔╝   ██║   "
echo "╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝  ╚═════╝    ╚═╝   "
echo "                                                    "
echo "                    By Abanoub                   "
echo -e "${NC}"

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   SSTP VPN Server - Full Installation${NC}"
echo -e "${BLUE}==============================================${NC}"
echo ""

echo -e "${YELLOW}WARNING: This will install an SSTP VPN server and configure PPP/firewall.${NC}"
echo -e "${YELLOW}   Please backup any important data before proceeding!${NC}"
echo ""

# ---------------------------------------------------------------------------
# 1. Detect the WAN/uplink interface
# ---------------------------------------------------------------------------
WAN_IF="$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' | head -1 || true)"
if [[ -z "$WAN_IF" ]]; then
    WAN_IF="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -1 || true)"
fi
if [[ -z "$WAN_IF" ]]; then
    echo -e "${RED}Could not auto-detect the uplink interface. Set it manually with WAN_IF=<iface> before running.${NC}" >&2
    exit 1
fi
echo -e "${CYAN}Detected uplink interface: ${GREEN}${WAN_IF}${NC}"

# Auto-detect the server's public IP (used as SSL certificate CN).
SERVER_IP="$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1 || true)"
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true)"
fi
if [[ -z "$SERVER_IP" ]]; then
    echo -e "${RED}Could not detect the server's public IP. Set SERVER_IP=<ip> before running.${NC}" >&2
    exit 1
fi
echo -e "${CYAN}Detected server IP: ${GREEN}${SERVER_IP}${NC}"
echo ""

# ---------------------------------------------------------------------------
# 2. Install system dependencies
# ---------------------------------------------------------------------------
echo -e "${CYAN}Updating system packages...${NC}"
sudo apt update -y

echo -e "${CYAN}Installing system dependencies...${NC}"
export DEBIAN_FRONTEND=noninteractive
sudo -E apt install -y ppp openssl iptables-persistent curl

echo -e "${GREEN}System dependencies installed${NC}"
echo ""

# ---------------------------------------------------------------------------
# 3. Install uv (Python version manager / venv tool)
# ---------------------------------------------------------------------------
echo -e "${CYAN}Installing uv...${NC}"
if command -v uv &>/dev/null; then
    echo -e "${GREEN}uv already installed${NC}"
else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Make uv available in this session
    export PATH="$HOME/.local/bin:$PATH"
fi
echo ""

# ---------------------------------------------------------------------------
# 4. Install Python 3.12 via uv
# ---------------------------------------------------------------------------
echo -e "${CYAN}Installing Python 3.12 via uv...${NC}"
uv python install 3.12

echo -e "${GREEN}Python 3.12 installed${NC}"
echo ""

# ---------------------------------------------------------------------------
# 5. Create venv with --seed (pre-installs pip/setuptools/wheel)
#    Lesson learned: without --seed the venv has no pip and installs fail.
# ---------------------------------------------------------------------------
echo -e "${CYAN}Creating Python virtual environment at /opt/sstpd-venv...${NC}"
if [[ -d /opt/sstpd-venv ]]; then
    echo -e "${YELLOW}Removing existing venv...${NC}"
    rm -rf /opt/sstpd-venv
fi
uv venv --python 3.12 --seed /opt/sstpd-venv

echo -e "${GREEN}Virtual environment created${NC}"
echo ""

# ---------------------------------------------------------------------------
# 6. Install sstp-server using the venv's own pip (explicit path)
#    Lesson learned: shell can cache a stale pip path (e.g. system Python 2.7).
#    Always use the full path to the venv's pip.
# ---------------------------------------------------------------------------
echo -e "${CYAN}Installing sstp-server...${NC}"
/opt/sstpd-venv/bin/pip install sstp-server

# Verify
if [[ ! -x /opt/sstpd-venv/bin/sstpd ]]; then
    echo -e "${RED}sstp-server binary not found after install — aborting.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}sstp-server installed${NC}"
echo ""

# ---------------------------------------------------------------------------
# 7. Generate self-signed SSL certificate
# ---------------------------------------------------------------------------
echo -e "${CYAN}Generating self-signed SSL certificate...${NC}"
if [[ -f /root/cert.pem ]] && [[ -f /root/key.pem ]]; then
    echo -e "${YELLOW}Existing certificate found — keeping it.${NC}"
else
    openssl req -x509 -newkey rsa:2048 \
        -keyout /root/key.pem \
        -out /root/cert.pem \
        -days 3650 -nodes \
        -subj "/CN=${SERVER_IP}"
    echo -e "${GREEN}SSL certificate generated (CN=${SERVER_IP})${NC}"
fi
echo ""

# ---------------------------------------------------------------------------
# 8. Create PPP options for SSTP
# ---------------------------------------------------------------------------
echo -e "${CYAN}Configuring PPP options...${NC}"
sudo bash -c 'cat > /etc/ppp/options.sstpd <<EOF
name sstpd
require-mschap-v2
nologfd
nodefaultroute
ms-dns 8.8.8.8
ms-dns 8.8.4.4
auth
debug
lock
proxyarp
EOF'

echo -e "${GREEN}PPP options configured (/etc/ppp/options.sstpd)${NC}"
echo ""

# ---------------------------------------------------------------------------
# 9. Configure chap-secrets (preserve existing users on re-run)
#    Server field = "sstpd" (must match "name" in options.sstpd)
# ---------------------------------------------------------------------------
echo -e "${CYAN}Configuring default users...${NC}"
if [[ -f /etc/ppp/chap-secrets ]] && grep -qvE '^\s*#|^\s*$' /etc/ppp/chap-secrets 2>/dev/null; then
    echo -e "${YELLOW}Existing chap-secrets found with users — keeping it untouched.${NC}"
else
    sudo bash -c 'cat > /etc/ppp/chap-secrets <<EOF
# Secrets for authentication using CHAP
# client    server    secret           IP addresses
user1       sstpd     ikasgfiuasgf     10.200.10.11
user2       sstpd     segheregtyeb     10.200.10.12
user3       sstpd     ba35rtyegbas     10.200.10.13
user4       sstpd     rtyasergbrge     10.200.10.14
user5       sstpd     vwehyaevwgfw     10.200.10.15
user6       sstpd     bwrvwefbtbwf     10.200.10.16
user7       sstpd     wlihfqbeuihf     10.200.10.17
EOF'
fi

# ---------------------------------------------------------------------------
# 10. Set chap-secrets permissions (root:www-data 660)
# ---------------------------------------------------------------------------
sudo chown root:www-data /etc/ppp/chap-secrets
sudo chmod 660 /etc/ppp/chap-secrets

echo -e "${GREEN}Default users configured${NC}"
echo ""

# ---------------------------------------------------------------------------
# 11. Enable IP forwarding
# ---------------------------------------------------------------------------
echo -e "${CYAN}Enabling IP forwarding...${NC}"
sudo bash -c 'echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-sstp-forward.conf'
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo -e "${GREEN}IP forwarding enabled${NC}"
echo ""

# ---------------------------------------------------------------------------
# 12. Create systemd service using printf (NOT heredoc)
#     Lesson learned: terminal wrapping can split the ExecStart line in heredocs,
#     producing an invalid unit file. printf writes the exact bytes we want.
#
#     Critical flags baked in:
#       -l 0.0.0.0         → fixes getaddrinfo crash on startup
#       --remote 10.200.0.0/16  → NOT 10.200.10.0/16 (that crashes with "host bits set")
#       --ciphers ...       → adds RSA ciphers for MikroTik RouterOS 6.x compatibility
#                             (without this, MikroTik shows "internal error (6)")
# ---------------------------------------------------------------------------
echo -e "${CYAN}Creating systemd service...${NC}"

printf '%s\n' \
    '[Unit]' \
    'Description=SSTP VPN Server' \
    'After=network.target' \
    '' \
    '[Service]' \
    'ExecStart=/opt/sstpd-venv/bin/sstpd -l 0.0.0.0 -p 4433 -c /root/cert.pem -k /root/key.pem --local 10.200.10.1 --remote 10.200.0.0/16 --pppd-config /etc/ppp/options.sstpd -v 5 --ciphers DEFAULT:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:@SECLEVEL=1' \
    'Restart=always' \
    'RestartSec=3' \
    'User=root' \
    '' \
    '[Install]' \
    'WantedBy=multi-user.target' \
    | sudo tee /etc/systemd/system/sstpd.service >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable sstpd >/dev/null 2>&1 || true

echo -e "${GREEN}systemd service created and enabled${NC}"
echo ""

# ---------------------------------------------------------------------------
# 13. Configure firewall rules (idempotent: -C checks before -A)
# ---------------------------------------------------------------------------
echo -e "${CYAN}Configuring firewall rules...${NC}"

# Open TCP 4433 for SSTP connections
sudo iptables -C INPUT -p tcp --dport 4433 -j ACCEPT 2>/dev/null || \
    sudo iptables -A INPUT -p tcp --dport 4433 -j ACCEPT

# NAT masquerade for SSTP client traffic
sudo iptables -t nat -C POSTROUTING -s 10.200.0.0/16 -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s 10.200.0.0/16 -o "$WAN_IF" -j MASQUERADE

# TCP MSS clamping for SSTP clients (prevents MTU black-hole issues)
sudo iptables -C FORWARD -p tcp --syn -s 10.200.0.0/16 -j TCPMSS --set-mss 1356 2>/dev/null || \
    sudo iptables -A FORWARD -p tcp --syn -s 10.200.0.0/16 -j TCPMSS --set-mss 1356

# Persist for reboot
sudo mkdir -p /etc/iptables
sudo sh -c "iptables-save > /etc/iptables/rules.v4"
sudo sh -c "iptables-save > /etc/iptables.rules"
sudo netfilter-persistent save 2>/dev/null || true

echo -e "${GREEN}Firewall rules configured (port 4433, NAT for 10.200.0.0/16, persisted)${NC}"
echo ""

# ---------------------------------------------------------------------------
# 14. Start sstpd and verify it is listening
# ---------------------------------------------------------------------------
echo -e "${CYAN}Starting SSTP server...${NC}"
sudo systemctl restart sstpd

echo ""
echo -e "${CYAN}Checking service status...${NC}"
sudo systemctl status sstpd --no-pager || true

echo ""
echo -e "${CYAN}Verifying sstpd is listening on TCP 4433...${NC}"
sleep 2
if sudo ss -tlnp 2>/dev/null | grep -q ':4433'; then
    echo -e "${GREEN}sstpd is listening on TCP 4433${NC}"
else
    echo -e "${RED}sstpd is NOT listening on TCP 4433 — install is incomplete. Check 'journalctl -u sstpd'.${NC}" >&2
    exit 1
fi

echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   SSTP VPN Server Installation Complete!${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# 15. Download and run the web panel installer
# ---------------------------------------------------------------------------
echo -e "${BLUE}Now installing Web Management Interface...${NC}"
TMP_GUI="$(mktemp)"
if curl -fsSL https://raw.githubusercontent.com/bakhtyarjaff98/sstp-manager/master/sas4-install.sh -o "$TMP_GUI"; then
    sudo bash "$TMP_GUI"
    rm -f "$TMP_GUI"
else
    rm -f "$TMP_GUI"
    echo -e "${RED}Failed to download the web interface installer. SSTP server is up; re-run sas4-install.sh later.${NC}" >&2
    exit 1
fi
