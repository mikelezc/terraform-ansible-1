resource "aws_instance" "lb" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.lb.id]

  root_block_device {
    volume_size = local.volume_size
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-lb"
    Role    = "loadbalancer"
    Project = var.project_name
  }
}

# Elastic IP: stable public IP for the LB — free while the instance is running.
# DuckDNS and CloudFront both point to this IP.
resource "aws_eip" "lb" {
  instance = aws_instance.lb.id

  tags = {
    Name    = "${var.project_name}-lb-eip"
    Project = var.project_name
  }
}

# DuckDNS update — only runs when duckdns_token is provided in terraform.tfvars
resource "null_resource" "duckdns_update" {
  count = var.duckdns_token != "" ? 1 : 0

  triggers = {
    lb_ip = aws_eip.lb.public_ip
  }

  provisioner "local-exec" {
    command = "curl -s 'https://www.duckdns.org/update?domains=${var.duckdns_subdomain}&token=${var.duckdns_token}&ip=${aws_eip.lb.public_ip}'"
  }
}
