# Render docker-compose for web instances and upload to S3
resource "aws_s3_object" "docker_compose_web" {
  bucket = aws_s3_bucket.config.id
  key    = "docker-compose.web.yml"

  content = templatefile("${path.module}/templates/docker-compose.web.yml.tpl", {
    db_private_ip = aws_instance.db.private_ip
    project_name  = var.project_name
  })

  content_type = "text/yaml"
  etag = md5(templatefile("${path.module}/templates/docker-compose.web.yml.tpl", {
    db_private_ip = aws_instance.db.private_ip
    project_name  = var.project_name
  }))
}

# Render nginx config for web instances and upload to S3
resource "aws_s3_object" "nginx_web_conf" {
  bucket = aws_s3_bucket.config.id
  key    = "nginx.web.conf"

  content = templatefile("${path.module}/templates/nginx.web.conf.tpl", {
    cloudfront_domain = aws_cloudfront_distribution.wordpress.domain_name
  })

  content_type = "text/plain"
  etag = md5(templatefile("${path.module}/templates/nginx.web.conf.tpl", {
    cloudfront_domain = aws_cloudfront_distribution.wordpress.domain_name
  }))
}

# Generate .env file with DB credentials and upload to S3
# Uses templatefile to avoid heredoc indentation issues with env file format
resource "aws_s3_object" "env_web" {
  bucket = aws_s3_bucket.config.id
  key    = ".env"

  content = templatefile("${path.module}/templates/env_web.tpl", {
    db_name          = var.db_name
    db_user          = var.db_user
    db_password      = var.db_password
    db_root_password = var.db_root_password
    domain_name      = aws_cloudfront_distribution.wordpress.domain_name
  })

  content_type = "text/plain"
  etag         = md5("${var.db_name}${var.db_user}${var.db_password}${var.db_root_password}")
}
