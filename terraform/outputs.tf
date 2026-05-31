output "cloudfront_domain" {
  description = "CloudFront distribution domain — use this URL to access the site"
  value       = "https://${aws_cloudfront_distribution.wordpress.domain_name}"
}

output "cloudfront_raw_domain" {
  description = "CloudFront domain name (without https://)"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}

output "alb_dns_name" {
  description = "ALB DNS name (internal, not for direct access)"
  value       = aws_lb.main.dns_name
}

output "db_public_ip" {
  description = "EC2-DB public IP — for SSH and Ansible"
  value       = aws_instance.db.public_ip
}

output "db_private_ip" {
  description = "EC2-DB private IP — used by web instances to connect to MariaDB"
  value       = aws_instance.db.private_ip
}

output "efs_dns_name" {
  description = "EFS DNS name — mounted on web instances for shared WordPress files"
  value       = aws_efs_file_system.wordpress.dns_name
}

output "s3_config_bucket" {
  description = "S3 bucket storing web instance configuration"
  value       = aws_s3_bucket.config.id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.web.name
}

output "deploy_instructions" {
  description = "Next steps after terraform apply"
  value       = <<-EOT

    ============================================================
    CLOUD-1 INFRASTRUCTURE READY
    ============================================================

    1. Run Ansible to configure the database:
       cd ../42_Cloud-1
       ansible-playbook -i inventory.ini playbook.yml

    2. Wait 3-5 minutes for web instances to bootstrap via cloud-init

    3. Access your WordPress site:
       ${aws_cloudfront_distribution.wordpress.domain_name}

    4. Scale up for demo:
       terraform apply -var="web_desired=4"

    5. Destroy everything when done:
       terraform destroy

    ============================================================
  EOT
}
