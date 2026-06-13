version: '3.8'

# Web instance services — MariaDB runs on EC2-DB (separate instance)
# DB host: ${db_private_ip}

services:
  nginx:
    image: nginx:latest
    container_name: nginx
    restart: always
    ports:
      - "80:80"
    volumes:
      - /home/ubuntu/data/wordpress:/var/www/html:ro
      - /home/ubuntu/data/nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /home/ubuntu/data/nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - wordpress
      - phpmyadmin
    networks:
      - inception_network

  wordpress:
    image: wordpress:6-fpm
    container_name: wordpress
    restart: always
    environment:
      WORDPRESS_DB_HOST: "${db_private_ip}:3306"
      WORDPRESS_DB_USER: $${DB_USER}
      WORDPRESS_DB_PASSWORD: $${DB_PASSWORD}
      WORDPRESS_DB_NAME: $${DB_NAME}
    volumes:
      - /home/ubuntu/data/wordpress:/var/www/html
    networks:
      - inception_network
    expose:
      - "9000"

  phpmyadmin:
    image: phpmyadmin:latest
    container_name: phpmyadmin
    restart: always
    environment:
      PMA_HOST: "${db_private_ip}"
      PMA_PORT: "3306"
      MYSQL_ROOT_PASSWORD: $${DB_ROOT_PASSWORD}
      PMA_ABSOLUTE_URI: "https://$${DOMAIN_NAME}/phpmyadmin/"
    networks:
      - inception_network
    expose:
      - "80"

networks:
  inception_network:
    driver: bridge
