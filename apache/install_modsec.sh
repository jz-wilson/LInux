#!/bin/bash

set -xe

# Install Mod_Security Requirements
apt install libapache2-modsecurity git -y

# Configure Mod_Security
mv /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf

# Enable Mod_Security
sed -i 's/SecRuleEngine.*/SecRuleEngine on/' /etc/modsecurity/modsecurity.conf
# Remove default CRS rules
rm -rf /usr/share/modsecurity-crs

# Download Recommended Settings
git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /usr/share/modsecurity-crs

# Setup New CRS Rules
cd /usr/share/modsecurity-crs || exit
mv crs-setup.conf.example crs-setup.conf

# Set rules to be used
cat <<EOF >/etc/apache2/mods-enabled/security2.conf
<IfModule security2_module>
    SecDataDir /var/cache/modsecurity
    IncludeOptional /etc/modsecurity/*.conf
    IncludeOptional "/usr/share/modsecurity-crs/*.conf"
    IncludeOptional "/usr/share/modsecurity-crs/rules/*.conf"
</IfModule>
EOF

# Restart Apache if Apache is not broken now
apachectl -t && systemctl restart apache2 || exit 1
