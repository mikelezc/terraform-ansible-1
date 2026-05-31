# Auto-generates the Ansible inventory file from Terraform outputs.
# Web instances are managed by cloud-init — only the DB needs Ansible.
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
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
  })
  filename        = "${path.module}/../inventory.ini"
  file_permission = "0644"
}
