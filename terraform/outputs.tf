output "cloudfront_domain" {
  description = "CloudFront distribution domain — primary site URL"
  value       = "https://${aws_cloudfront_distribution.wordpress.domain_name}"
}

output "cloudfront_raw_domain" {
  description = "CloudFront domain name (without https://)"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}

output "lb_public_ip" {
  description = "Nginx LB Elastic IP — also the CloudFront origin and DuckDNS target"
  value       = aws_eip.lb.public_ip
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
  description = "Auto Scaling Group name — used by Ansible loadbalancer role to discover web instance IPs"
  value       = aws_autoscaling_group.web.name
}

output "sns_confirm_note" {
  description = "Reminder to confirm the SNS email subscription"
  value       = var.alert_email != "" ? "ACTION REQUIRED: check ${var.alert_email} and click the AWS confirmation link to activate alerts." : null
}

output "deploy_instructions" {
  description = "Next steps after terraform apply"
  value       = <<-EOT

    ============================================================
    CLOUD-1 INFRASTRUCTURE READY
    ============================================================

    LB Elastic IP:     ${aws_eip.lb.public_ip}
    Site URL:          https://${aws_cloudfront_distribution.wordpress.domain_name}

    Ansible ran automatically — LB and DB are configured.

    1. Wait ~5 min for web instances to bootstrap via cloud-init
       (AWS Console → EC2 → Instances to monitor progress)

    2. Access site: https://${aws_cloudfront_distribution.wordpress.domain_name}

    3. After scaling (terraform apply -var="web_desired=N"), refresh LB config:
       cd /workspace/ansible
       ansible-playbook -i inventory.ini playbook.yml -l lb

    4. Destroy everything when done:
       terraform destroy

    ============================================================
  EOT
}
