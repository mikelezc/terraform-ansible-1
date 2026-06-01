resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    lb_public_ip         = aws_eip.lb.public_ip
    db_public_ip         = aws_instance.db.public_ip
    db_private_ip        = aws_instance.db.private_ip
    efs_dns_name         = aws_efs_file_system.wordpress.dns_name
    cloudfront_domain    = aws_cloudfront_distribution.wordpress.domain_name
    s3_config_bucket     = aws_s3_bucket.config.id
    ssh_private_key_path = var.ssh_private_key_path
    project_name         = var.project_name
    db_name              = var.db_name
    db_user              = var.db_user
    db_password          = var.db_password
    db_root_password     = var.db_root_password
    asg_name             = aws_autoscaling_group.web.name
    aws_region           = var.aws_region
  })
  filename        = "${path.module}/../inventory.ini"
  file_permission = "0644"
}
