resource "aws_cloudfront_distribution" "wordpress" {
  comment     = "${var.project_name} WordPress CDN"
  enabled     = true
  price_class = "PriceClass_100" # Use only North America and Europe (cheapest)

  # Origin: ALB (HTTP only — CloudFront terminates HTTPS for users)
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "${var.project_name}-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Forward Host header so WordPress sees the right domain
    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
  }

  # Default behavior: forward everything to ALB (dynamic content)
  default_cache_behavior {
    target_origin_id       = "${var.project_name}-alb-origin"
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

  # Cache behavior for WordPress static assets — these are served from CDN cache
  ordered_cache_behavior {
    path_pattern           = "/wp-content/*"
    target_origin_id       = "${var.project_name}-alb-origin"
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
    target_origin_id       = "${var.project_name}-alb-origin"
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

  # Use CloudFront's default certificate (for *.cloudfront.net domain)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name    = "${var.project_name}-cloudfront"
    Project = var.project_name
  }
}
