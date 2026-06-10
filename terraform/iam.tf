# IAM role that web instances assume — allows reading config from S3
resource "aws_iam_role" "web_instance" {
  name = "${var.project_name}-web-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${var.project_name}-web-instance-role"
    Project = var.project_name
  }
}

# IAM policy to allow web instances to read config from S3
resource "aws_iam_role_policy" "web_s3_read" {
  name = "${var.project_name}-web-s3-read"
  role = aws_iam_role.web_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.config.arn,
        "${aws_s3_bucket.config.arn}/*"
      ]
    }]
  })
}

# IAM instance profile for web instances to attach the role
resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-web-instance-profile"
  role = aws_iam_role.web_instance.name
}
