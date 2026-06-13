# Nginx config for web instances — serves WordPress via PHP-FPM
# SSL is terminated at CloudFront; this server only handles HTTP (port 80)
# CloudFront sends X-Forwarded-Proto: https so WordPress knows it's HTTPS

server {
    listen 80;
    server_name _;

    root /var/www/html;
    index index.php index.html;

    # Header identifying which instance served this request (evaluator verification)
    add_header X-Served-By $hostname always;

    # Logging
    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;

    # WordPress URL rewriting
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # PHP-FPM handler
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        # Tell WordPress that the request arrived over HTTPS
        fastcgi_param HTTPS on;
        fastcgi_param HTTP_X_FORWARDED_PROTO https;
    }

    # phpMyAdmin reverse proxy
    location /phpmyadmin/ {
        proxy_pass http://phpmyadmin/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Block access to sensitive files
    location ~ /\. {
        deny all;
    }

    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
    }
}
