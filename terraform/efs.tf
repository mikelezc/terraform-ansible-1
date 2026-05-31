resource "aws_efs_file_system" "wordpress" {
  creation_token   = "${var.project_name}-wordpress-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name    = "${var.project_name}-wordpress-efs"
    Project = var.project_name
  }
}

# Mount target in every subnet of the default VPC so web instances in any AZ can mount
resource "aws_efs_mount_target" "wordpress" {
  for_each = toset(data.aws_subnets.default.ids)

  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}
