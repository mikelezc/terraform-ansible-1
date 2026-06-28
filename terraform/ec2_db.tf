resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.db.id]

  root_block_device {
    volume_size = local.volume_size
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-db"
    Role    = "database"
    Project = var.project_name
  }
}
