#!/bin/bash
apt-get update -y
apt-get install -y nginx nodejs npm git

# Clone the React app
git clone https://github.com/0dow0ri7s3/my-react-app.git /home/react-admin/my-react-app
cd /home/react-admin/my-react-app

# Customize with your name and date
sed -i 's/Your Full Name/Odoworitse Ab. Afari/g' src/App.js
sed -i 's/DD\/MM\/YYYY/19\/03\/2026/g' src/App.js

# Install dependencies and build
npm install
npm run build

# Deploy to Nginx
rm -rf /var/www/html/*
cp -rr build/* /var/www/html/
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Configure Nginx for React routing
echo 'server {
  listen 80;
  server_name _;
  root /var/www/html;
  index index.html;
  location / {
    try_files $uri /index.html;
  }
  error_page 404 /index.html;
}' > /etc/nginx/sites-available/default

systemctl restart nginx
systemctl enable nginx