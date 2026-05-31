resource "aws_cloudfront_distribution" "wordpress" {
  comment     = "${var.project_name} WordPress CDN"
  enabled     = true
  price_class = "PriceClass_100" # North America + Europe only (cheapest)

  # Origin: Nginx LB EC2 via its AWS public DNS hostname.
  # CloudFront does not accept raw IP addresses as origins — must be a hostname.
  # AWS assigns ec2-W-X-Y-Z.<region>.compute.amazonaws.com to every Elastic IP.
  origin {
    domain_name = "ec2-${replace(aws_eip.lb.public_ip, ".", "-")}.${var.aws_region}.compute.amazonaws.com"
    origin_id   = "${var.project_name}-lb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Tell backend that the original request arrived over HTTPS
    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
  }

  # Default behavior: pass-through for dynamic content (WP admin, posts, etc.)
  default_cache_behavior {
    target_origin_id       = "${var.project_name}-lb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "CloudFront-Forwarded-Proto"]
      cookies {
        forward = "all"
      }
    }

    # No caching for dynamic content
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # Cache WordPress theme/plugin assets — this is what makes it a CDN
  ordered_cache_behavior {
    path_pattern           = "/wp-content/*"
    target_origin_id       = "${var.project_name}-lb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      headers      = []
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400    # 1 day
    max_ttl     = 31536000 # 1 year
  }

  ordered_cache_behavior {
    path_pattern           = "/wp-includes/*"
    target_origin_id       = "${var.project_name}-lb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      headers      = []
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Default CloudFront certificate (for *.cloudfront.net domain)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name    = "${var.project_name}-cloudfront"
    Project = var.project_name
  }
}
