#!/bin/bash

# ==============================================================================
# 🚀 SAS4 SSTP Manager - Web Interface Installer
# ==============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
echo ""
# Variables
REPO_URL="https://github.com/bakhtyarjaff98/sstp-manager.git"
TARGET_DIR="/opt/sas4/site/sstp-manager/"
CHAP_SECRETS="/etc/ppp/chap-secrets"
PORTS_CONF="/etc/apache2/ports.conf"
CERT_PATH="/etc/ssl/certs/sstp-manager.pem"
KEY_PATH="/etc/ssl/private/sstp-manager.key"
HTTP_PORT=8090
HTTPS_PORT=8099
HTTP_CONF="/etc/apache2/sites-available/sstp-manager-http.conf"
SSL_CONF="/etc/apache2/sites-available/sstp-manager-ssl.conf"

echo -e "${YELLOW}🚀 Starting SSTP Manager Web Interface Installation...${NC}"
echo ""

# Install Apache & dependencies
echo -e "${CYAN}📦 Installing required packages...${NC}"
apt-get update
apt-get install -y git unzip curl apache2 openssl libapache2-mod-php
a2enmod ssl

echo -e "${GREEN}✅ Required packages installed${NC}"
echo ""

# Remove old L2TP vhosts if present (prevents them shadowing the SSTP vhost on
# servers that previously ran l2tp-manager).
for old_conf in l2tp-manager-http l2tp-manager-ssl; do
    if [ -f "/etc/apache2/sites-enabled/${old_conf}.conf" ]; then
        a2dissite "${old_conf}.conf" >/dev/null 2>&1 || true
        echo -e "${YELLOW}Disabled old ${old_conf} vhost${NC}"
    fi
done

# Clone the project
echo -e "${CYAN}📥 Cloning SSTP Manager repository...${NC}"
if [ -d "$TARGET_DIR" ]; then
    echo -e "${YELLOW}Removing existing directory $TARGET_DIR${NC}"
    rm -rf "$TARGET_DIR"
fi

echo -e "${YELLOW}Cloning repository to $TARGET_DIR${NC}"
git clone $REPO_URL $TARGET_DIR

echo -e "${GREEN}✅ Repository cloned successfully${NC}"
echo ""

# Permissions
echo -e "${CYAN}🔐 Setting up permissions...${NC}"
# chap-secrets must be read+writable by the panel (Apache/www-data) and pppd (root).
# root:www-data 660 — not 666 (world-readable secrets), not 600 (locks out the panel:
# users vanish from the UI and new users all collide on the same IP).
if [ -f "$CHAP_SECRETS" ]; then
    chown root:www-data "$CHAP_SECRETS"
    chmod 660 "$CHAP_SECRETS"
fi
chown -R www-data:www-data $TARGET_DIR
chmod -R 755 $TARGET_DIR

echo -e "${GREEN}✅ Permissions configured${NC}"
echo ""

# Ensure Apache listens on both ports
echo -e "${CYAN}🌐 Configuring Apache ports...${NC}"
for port in $HTTP_PORT $HTTPS_PORT; do
    if ! grep -q "Listen $port" "$PORTS_CONF"; then
        echo "Listen $port" >> "$PORTS_CONF"
        echo -e "${YELLOW}Added port $port to Apache configuration${NC}"
    else
        echo -e "${GREEN}Port $port already configured${NC}"
    fi
done

echo -e "${GREEN}✅ Apache ports configured${NC}"
echo ""

# Generate self-signed SSL certificate if needed
echo -e "${CYAN}🔒 Generating SSL certificate...${NC}"
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -subj "/C=EG/ST=Cairo/L=Cairo/O=SAS4/OU=IT/CN=sas4group.net"
    echo -e "${GREEN}✅ New SSL certificate generated${NC}"
else
    echo -e "${GREEN}✅ SSL certificate already exists${NC}"
fi
echo ""

# HTTP VirtualHost (for /sstp-manager only)
echo -e "${CYAN}⚙️  Configuring HTTP VirtualHost...${NC}"
if [ ! -f "$HTTP_CONF" ]; then
cat <<EOL > "$HTTP_CONF"
<VirtualHost *:$HTTP_PORT>
    Alias /sstp-manager $TARGET_DIR
    <Directory $TARGET_DIR>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/sstp-http-error.log
    CustomLog \${APACHE_LOG_DIR}/sstp-http-access.log combined
</VirtualHost>
EOL
    a2ensite sstp-manager-http.conf
    echo -e "${GREEN}✅ HTTP VirtualHost created and enabled${NC}"
else
    echo -e "${GREEN}✅ HTTP VirtualHost already configured${NC}"
fi
echo ""

# HTTPS VirtualHost (for /sstp-manager only)
echo -e "${CYAN}⚙️  Configuring HTTPS VirtualHost...${NC}"
if [ ! -f "$SSL_CONF" ]; then
cat <<EOL > "$SSL_CONF"
<VirtualHost *:$HTTPS_PORT>
    SSLEngine on
    SSLCertificateFile $CERT_PATH
    SSLCertificateKeyFile $KEY_PATH

    Alias /sstp-manager $TARGET_DIR
    <Directory $TARGET_DIR>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/sstp-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/sstp-ssl-access.log combined
</VirtualHost>
EOL
    a2ensite sstp-manager-ssl.conf
    echo -e "${GREEN}✅ HTTPS VirtualHost created and enabled${NC}"
else
    echo -e "${GREEN}✅ HTTPS VirtualHost already configured${NC}"
fi
echo ""

# Reload Apache to apply changes
echo -e "${CYAN}🔄 Reloading Apache configuration...${NC}"
systemctl reload apache2

echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   Installation Complete! 🎉${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""
echo -e "${BLUE}🌐 Access your SSTP Manager:${NC}"
echo -e "  🔓 HTTP : http://your-ip:$HTTP_PORT/sstp-manager/"
echo -e "  🔐 HTTPS: https://your-ip:$HTTPS_PORT/sstp-manager/"
echo ""
echo -e "${YELLOW}📝 Default Credentials:${NC}"
echo -e "  👤 Username: admin"
echo -e "  🔑 Password: change@me (Please change this immediately)"
echo ""
echo -e "${PURPLE}💡 Tip: For security, access via HTTPS and change the default password!${NC}"
echo ""