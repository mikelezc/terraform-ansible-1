#!/bin/bash
# Cloud-init script for web instances
# Runs once on first boot — installs Docker, mounts EFS, downloads config, starts services
set -euo pipefail
exec > /var/log/cloud-init-wordpress.log 2>&1

echo "=== [cloud-init] Starting WordPress web instance setup ==="

# ─── Dependencies ──────────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y --no-install-recommends \
  docker.io \
  nfs-common \
  awscli \
  openssl \
  python3-cryptography

# ─── Docker ───────────────────────────────────────────────────────────────────
systemctl enable docker
systemctl start docker

# Docker Compose v2
curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null || true

usermod -aG docker ubuntu

# ─── Directory structure ───────────────────────────────────────────────────────
mkdir -p /home/ubuntu/data/wordpress
mkdir -p /home/ubuntu/data/nginx/ssl
mkdir -p /home/ubuntu/inception

# ─── EFS mount (shared WordPress files) ───────────────────────────────────────
echo "=== [cloud-init] Mounting EFS ==="

# Retry EFS mount — mount targets may not be ready immediately
for i in $(seq 1 10); do
  if mount -t nfs4 \
    -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
    "${efs_dns_name}:/" /home/ubuntu/data/wordpress; then
    echo "EFS mounted successfully on attempt $i"
    break
  fi
  echo "Mount attempt $i failed, retrying in 15s..."
  sleep 15
done

# Persist mount across reboots
echo "${efs_dns_name}:/ /home/ubuntu/data/wordpress nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab

# ─── Download config from S3 ──────────────────────────────────────────────────
echo "=== [cloud-init] Downloading config from S3 ==="

export AWS_DEFAULT_REGION="${aws_region}"

# Retry S3 download — IAM role propagation may take a few seconds
for i in $(seq 1 10); do
  if aws s3 cp "s3://${s3_bucket}/docker-compose.web.yml" /home/ubuntu/inception/docker-compose.yml && \
     aws s3 cp "s3://${s3_bucket}/nginx.web.conf" /home/ubuntu/data/nginx/nginx.conf && \
     aws s3 cp "s3://${s3_bucket}/.env" /home/ubuntu/inception/.env; then
    echo "S3 config downloaded successfully on attempt $i"
    break
  fi
  echo "S3 download attempt $i failed, retrying in 10s..."
  sleep 10
done

chmod 600 /home/ubuntu/inception/.env

# ─── Self-signed SSL cert (used by Nginx internally) ──────────────────────────
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /home/ubuntu/data/nginx/ssl/server.key \
  -out /home/ubuntu/data/nginx/ssl/server.crt \
  -subj "/C=ES/ST=Madrid/L=Madrid/O=cloud1/CN=${cloudfront_domain}"

# ─── Permissions ──────────────────────────────────────────────────────────────
chown -R ubuntu:ubuntu /home/ubuntu/

# ─── Start services ───────────────────────────────────────────────────────────
echo "=== [cloud-init] Starting Docker Compose stack ==="
cd /home/ubuntu/inception
docker-compose up -d

# ─── Wait for WordPress to initialize ─────────────────────────────────────────
echo "=== [cloud-init] Waiting for WordPress wp-config.php ==="
for i in $(seq 1 24); do
  if [ -f /home/ubuntu/data/wordpress/wp-config.php ]; then
    echo "wp-config.php found after ${i}×5s"
    break
  fi
  sleep 5
done

# ─── Patch wp-config.php ──────────────────────────────────────────────────────
WPCONFIG="/home/ubuntu/data/wordpress/wp-config.php"
if [ -f "$WPCONFIG" ]; then
  # Only patch once — check for marker
  if ! grep -q "CLOUD1 MANAGED BLOCK" "$WPCONFIG"; then
    # Insert before "That's all, stop editing!" line
    sed -i "/That's all, stop editing/i\\
\\
// CLOUD1 MANAGED BLOCK\\
define( 'WP_HOME', 'https://' . \$_SERVER['HTTP_HOST'] );\\
define( 'WP_SITEURL', 'https://' . \$_SERVER['HTTP_HOST'] );\\
define( 'WP_CONTENT_URL', 'https://${cloudfront_domain}/wp-content' );\\
// END CLOUD1 MANAGED BLOCK\\
" "$WPCONFIG"
    echo "wp-config.php patched successfully"
  else
    echo "wp-config.php already patched — skipping"
  fi
else
  echo "WARNING: wp-config.php not found — WordPress may not have initialized yet"
fi

echo "=== [cloud-init] Web instance setup complete ==="
