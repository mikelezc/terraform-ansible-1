# ─── Load Balancer Security Group ─────────────────────────────────────────────
# Public-facing EC2 Nginx LB: HTTP/HTTPS from anywhere, SSH from deployer only

resource "aws_security_group" "lb" {
  name        = "${var.project_name}-lb-sg"
  description = "Nginx LB: HTTP/HTTPS from internet, SSH from deployer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from deployer"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-lb-sg"
    Project = var.project_name
  }
}

# ─── Web Instances Security Group ──────────────────────────────────────────────
# Only receives HTTP from the Nginx LB; SSH from deployer only

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web instances: HTTP from LB only, SSH from deployer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from Nginx LB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  ingress {
    description = "SSH from deployer"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-web-sg"
    Project = var.project_name
  }
}

# ─── Database Security Group ───────────────────────────────────────────────────
# MariaDB only accessible from web instances; SSH from deployer only

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "DB: MariaDB from web SG only, SSH from deployer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MariaDB from web instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  ingress {
    description = "SSH from deployer"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-db-sg"
    Project = var.project_name
  }
}

# ─── EFS Security Group ────────────────────────────────────────────────────────
# NFS port only from web instances

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "EFS: NFS from web instances only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "NFS from web instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-efs-sg"
    Project = var.project_name
  }
}
