resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-web-config-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-web-config"
    Project = var.project_name
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Disabled"
  }
}

# Block all public access — only web instances (via IAM role) can read
resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
