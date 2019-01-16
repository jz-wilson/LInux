#!/bin/bash

setfacl -dRm u:www-data:rwX,g:www-data:rwX .
chown -R www-data:www-data .
chmod -R ug+s .
find . -type d -exec chmod 775 {} +
find . -type f -exec chmod 664 {} +
chmod -R 775 node_modules vendor
find . -name '.htaccess' -exec chmod 600 {} \;
find . -name 'web.config' -exec chmod 600 {} \;
apachectl -t
service apache2 reload
