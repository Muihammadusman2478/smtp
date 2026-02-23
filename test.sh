#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "======================================"
echo "POSTFIX CONFIGURATION"
echo "======================================"
cat /etc/postfix/main.cf
echo ""

BASE_DIR="/home/master/applications"

cd "$BASE_DIR" || exit 1

read -p "Enter the domain: " DOMAIN
echo ""

echo "Searching for '$DOMAIN' in conf files..."

APP_MATCH=$(grep -rni "$DOMAIN" */conf/* 2>/dev/null | head -n1 | cut -d'/' -f1)

if [ -z "$APP_MATCH" ]; then
    echo "No matching application found."
    exit 1
fi

echo -e "${CYAN}Application identified:${NC} $APP_MATCH"

APP_DIR="$BASE_DIR/$APP_MATCH"
NGINX_CONF="/etc/nginx/sites-enabled/$APP_MATCH"

WEBROOT=$(grep -i "root" "$NGINX_CONF" | head -n1 | awk '{print $2}' | tr -d ';')

echo ""
echo "======================================"
echo -e "${GREEN}✔ Webroot detected:${NC}"
echo -e "${GREEN}$WEBROOT${NC}"
echo "======================================"

cd "$WEBROOT" || exit 1

# WordPress Detection
IS_WORDPRESS=0
if grep -r "wordpress-[0-9]*-[0-9]*\.cloudwaysapps\.com" "$APP_DIR/conf/" >/dev/null 2>&1; then
    IS_WORDPRESS=1
fi

if [ "$IS_WORDPRESS" -eq 1 ]; then
    echo -e "${GREEN}✔ WordPress application detected.${NC}"
else
    echo "Non-WordPress application detected."
fi

# WordPress Plugin Check
if [ "$IS_WORDPRESS" -eq 1 ]; then

    if command -v wp >/dev/null 2>&1; then

        echo ""
        echo "Checking for wp-mail-smtp plugin..."

        PLUGIN_OUTPUT=$(wp --allow-root --skip-plugins --skip-themes --skip-packages plugin list | grep -i "wp-mail-smtp")

        if [ -n "$PLUGIN_OUTPUT" ]; then
            echo -e "${GREEN}✔ wp-mail-smtp plugin found:${NC}"
            echo -e "${GREEN}$PLUGIN_OUTPUT${NC}"
        else
            echo -e "${YELLOW}wp-mail-smtp plugin not found.${NC}"
        fi

        echo ""
        echo "Fetching wp_mail_smtp option..."

        SMTP_OPTION=$(wp --allow-root option get wp_mail_smtp)

        if [ -n "$SMTP_OPTION" ]; then
            echo -e "${GREEN}✔ wp_mail_smtp configuration:${NC}"
            echo -e "${GREEN}$SMTP_OPTION${NC}"
        fi

    fi
fi

# Ask From Address
echo ""
read -p "Enter the From email address: " FROM_EMAIL
echo ""

# Create mail() script
MAIL_FILE="$WEBROOT/mail-test.php"

cat > "$MAIL_FILE" <<EOF
<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);

\$from = "$FROM_EMAIL";
\$to = "muhammad.usman@cloudways.com";
\$subject = "PHP Mail Test script";
\$message = "This is a test to check the PHP Mail functionality";
\$headers = "From: " . \$from;

mail(\$to, \$subject, \$message, \$headers);

echo "Test email sent using mail()";
?>
EOF

echo -e "${GREEN}✔ mail() test script created${NC}"

# Create wp_mail() script if WordPress
if [ "$IS_WORDPRESS" -eq 1 ]; then

    WP_MAIL_FILE="$WEBROOT/wp-mail-test.php"

    cat > "$WP_MAIL_FILE" <<EOF
<?php
require('wp-load.php');

\$from = "$FROM_EMAIL";
\$to = "muhammad.usman@cloudways.com";
\$subject = "PHP WP Mail Test script";
\$message = "This is a test to check the PHP WP Mail functionality";
\$headers = "From: " . \$from;

wp_mail(\$to, \$subject, \$message, \$headers);

echo "Test email sent using wp_mail()";
?>
EOF

    echo -e "${GREEN}✔ wp_mail() test script created${NC}"
fi

# Print both files
echo ""
echo "======================================"
echo -e "${CYAN}Generated mail-test.php:${NC}"
echo "======================================"
cat "$MAIL_FILE"

if [ "$IS_WORDPRESS" -eq 1 ]; then
    echo ""
    echo "======================================"
    echo -e "${CYAN}Generated wp-mail-test.php:${NC}"
    echo "======================================"
    cat "$WP_MAIL_FILE"
fi

echo ""
echo -e "${GREEN}✔ Script completed successfully.${NC}"

# DNS Check
echo ""
echo "======================================"
echo "DNS Records for $DOMAIN"
echo "======================================"

echo -e "${CYAN}A Record:${NC}"
dig +short A $DOMAIN

echo ""
echo -e "${CYAN}MX Record:${NC}"
dig +short MX $DOMAIN

echo ""
echo -e "${CYAN}TXT Records:${NC}"
dig +short TXT $DOMAIN

echo ""
echo -e "${CYAN}DMARC Record:${NC}"
dig +short TXT _dmarc.$DOMAIN

# Final Directory Change
cd "$WEBROOT"

echo ""
echo -e "${GREEN}✔ Final directory:${NC} $(pwd)"
