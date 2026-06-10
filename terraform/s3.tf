resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-web-config-${random_id.suffix.hex}"
  force_destroy = true				# Automatically delete all objects when destroying the bucket

  tags = {
    Name    = "${var.project_name}-web-config"
    Project = var.project_name
  }
}

# We store the Ansible inventory and WP-CLI config in S3 for easy access by web instances (via IAM role)
resource "random_id" "suffix" {
  byte_length = 4					# We add a random suffix to the bucket name to ensure uniqueness (S3 bucket names are global).
}

# We disable versioning to avoid extra costs for this demo, 
# but in production you should usually enable it

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Disabled"
  }
}

# Block all public access — only web instances (via IAM role) can read it

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
