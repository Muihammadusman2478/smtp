#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# If sourced, "exit" would kill the SSH session.
# Use fail()/ok() helpers to safely stop without closing the connection.
fail() { echo -e "${YELLOW}❌ $1${NC}"; return 1 2>/dev/null || exit 1; }
ok()   { echo -e "${GREEN}✔ $1${NC}"; }

echo "======================================"
echo "POSTFIX CONFIGURATION"
echo "======================================"
cat /etc/postfix/main.cf
echo ""

BASE_DIR="/home/master/applications"
cd "$BASE_DIR" || fail "Applications directory not found: $BASE_DIR"

read -p "Enter the domain: " DOMAIN
echo ""

echo "Searching for '$DOMAIN' in conf files..."

APP_MATCH=$(grep -rni "$DOMAIN" */conf/* 2>/dev/null | head -n1 | cut -d'/' -f1)

if [ -z "$APP_MATCH" ]; then
  echo -e "${YELLOW}❌ No matching application found for domain: ${DOMAIN}${NC}"
  echo -e "${CYAN}Tip:${NC} Try searching with www.${DOMAIN} or check domain mapping in app conf."
  # Do NOT exit (would close SSH when sourced). Just return safely.
  return 0 2>/dev/null || exit 0
fi

echo -e "${CYAN}Application identified:${NC} $APP_MATCH"

APP_DIR="$BASE_DIR/$APP_MATCH"
NGINX_CONF="/etc/nginx/sites-enabled/$APP_MATCH"

[ -f "$NGINX_CONF" ] || fail "Nginx config not found: $NGINX_CONF"

WEBROOT=$(grep -i "root" "$NGINX_CONF" | head -n1 | awk '{print $2}' | tr -d ';')
[ -n "$WEBROOT" ] || fail "Webroot not detected from nginx config ($NGINX_CONF)."

echo ""
echo "======================================"
echo -e "${GREEN}✔ Webroot detected:${NC}"
echo -e "${GREEN}$WEBROOT${NC}"
echo "======================================"

cd "$WEBROOT" || fail "Unable to access webroot: $WEBROOT"

# WordPress Detection (based on Cloudways WP system domain pattern)
IS_WORDPRESS=0
if grep -r "wordpress-[0-9]*-[0-9]*\.cloudwaysapps\.com" "$APP_DIR/conf/" >/dev/null 2>&1; then
  IS_WORDPRESS=1
fi

if [ "$IS_WORDPRESS" -eq 1 ]; then
  ok "WordPress application detected."
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
      ok "wp-mail-smtp plugin found:"
      echo -e "${GREEN}$PLUGIN_OUTPUT${NC}"
    else
      echo -e "${YELLOW}wp-mail-smtp plugin not found.${NC}"
    fi

    echo ""
    echo "Fetching wp_mail_smtp option..."
    SMTP_OPTION=$(wp --allow-root option get wp_mail_smtp 2>/dev/null)

    if [ -n "$SMTP_OPTION" ]; then
      ok "wp_mail_smtp configuration:"
      echo -e "${GREEN}$SMTP_OPTION${NC}"
    else
      echo -e "${YELLOW}(No wp_mail_smtp option found or WP-CLI couldn't read it.)${NC}"
    fi
  else
    echo -e "${YELLOW}WP CLI not found.${NC}"
  fi
fi

# Ask From Address
echo ""
read -p "Enter the From email address: " FROM_EMAIL
echo ""

# Shared email content (same for both)
EMAIL_SUBJECT="Email Functionality Validation from Your Cloudways Server"

EMAIL_BODY_COMMON=$(cat <<'EOT'
Dear Customer,

You are receiving this email since you have tried the Send Test Email feature of your Cloudways managed server. We confirm that it works!

You can now send transactional emails from your application, which means contact forms, order emails, etc. should be working. To setup application specific senders, please refer to this knowledge base article.

You are now able to send transactional emails from your Application, which means Contact Forms, Order Emails etc should be working.

Should you still have any difficulties, please do not hesitate to reach us over Live Chat.

Thank You.

Cloudways Team.
Powered By PO Team
EOT
)

# Create mail() script
MAIL_FILE="$WEBROOT/mail-test.php"

cat > "$MAIL_FILE" <<EOF
<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);

\$from = "$FROM_EMAIL";
\$to = "muhammad.usman@cloudways.com";
\$subject = "$EMAIL_SUBJECT";

\$message = <<<EOT
$EMAIL_BODY_COMMON

[Sent via: mail()]
EOT;

\$headers  = "From: \$from\\r\\n";
\$headers .= "Reply-To: \$from\\r\\n";
\$headers .= "MIME-Version: 1.0\\r\\n";
\$headers .= "Content-Type: text/plain; charset=UTF-8\\r\\n";
\$headers .= "Content-Transfer-Encoding: 8bit\\r\\n";

mail(\$to, \$subject, \$message, \$headers);

echo "Test email sent using mail()";
?>
EOF

ok "mail() test script created"

# Create wp_mail() script if WordPress
if [ "$IS_WORDPRESS" -eq 1 ]; then
  WP_MAIL_FILE="$WEBROOT/wp-mail-test.php"

  cat > "$WP_MAIL_FILE" <<EOF
<?php
require('wp-load.php');

\$from = "$FROM_EMAIL";
\$to = "muhammad.usman@cloudways.com";
\$subject = "$EMAIL_SUBJECT";

\$message = <<<EOT
$EMAIL_BODY_COMMON

[Sent via: wp_mail()]
EOT;

\$headers = array(
  "From: {\$from}",
  "Reply-To: {\$from}",
  "Content-Type: text/plain; charset=UTF-8"
);

wp_mail(\$to, \$subject, \$message, \$headers);

echo "Test email sent using wp_mail()";
?>
EOF

  ok "wp_mail() test script created"
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
ok "Script completed successfully."

# DNS Check
echo ""
echo "======================================"
echo "DNS Records for $DOMAIN"
echo "======================================"

echo -e "${CYAN}A Record:${NC}"
dig +short A "$DOMAIN"

echo ""
echo -e "${CYAN}MX Record:${NC}"
dig +short MX "$DOMAIN"

echo ""
echo -e "${CYAN}TXT Records:${NC}"
dig +short TXT "$DOMAIN"

echo ""
echo -e "${CYAN}DMARC Record:${NC}"
dig +short TXT "_dmarc.$DOMAIN"

# Final Directory Change (persists when run via source)
cd "$WEBROOT" || fail "Could not cd into webroot at the end: $WEBROOT"
echo ""
ok "Final directory: $(pwd)"
