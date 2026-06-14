locals {
  docker_compose_web_content = templatefile("${path.module}/templates/docker-compose.web.yml.tpl", {
    db_private_ip = aws_instance.db.private_ip
    project_name  = var.project_name
  })

  nginx_web_conf_content = file("${path.module}/templates/nginx.web.conf.tpl")

  env_web_content = templatefile("${path.module}/templates/env_web.tpl", {
    db_name          = var.db_name
    db_user          = var.db_user
    db_password      = var.db_password
    db_root_password = var.db_root_password
    domain_name      = aws_cloudfront_distribution.wordpress.domain_name
  })
}

resource "aws_s3_object" "docker_compose_web" {
  bucket       = aws_s3_bucket.config.id
  key          = "docker-compose.web.yml"
  content      = local.docker_compose_web_content
  content_type = "text/yaml"
  etag         = md5(local.docker_compose_web_content)
}

resource "aws_s3_object" "nginx_web_conf" {
  bucket       = aws_s3_bucket.config.id
  key          = "nginx.web.conf"
  content      = local.nginx_web_conf_content
  content_type = "text/plain"
  etag         = md5(local.nginx_web_conf_content)
}

resource "aws_s3_object" "env_web" {
  bucket       = aws_s3_bucket.config.id
  key          = ".env"
  content      = local.env_web_content
  content_type = "text/plain"
  etag         = md5(local.env_web_content)
}
