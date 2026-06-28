resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.web.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }

  # Cloud-init script rendered with actual values — runs once on instance startup
  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    efs_dns_name           = aws_efs_file_system.wordpress.dns_name
    s3_bucket              = aws_s3_bucket.config.id
    cloudfront_domain      = aws_cloudfront_distribution.wordpress.domain_name
    aws_region             = var.aws_region
    wp_title               = var.wp_title
    wp_admin_user          = var.wp_admin_user
    wp_admin_password      = var.wp_admin_password
    wp_admin_email         = var.wp_admin_email
    docker_compose_version = var.docker_compose_version
  }))

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = local.volume_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-web"
      Role    = "webserver"
      Project = var.project_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-web-asg"
  min_size            = var.web_min_size
  desired_capacity    = var.web_desired
  max_size            = var.web_max_size
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  # EC2 health check: ASG replaces instances that fail AWS EC2 status checks
  # (e.g. hardware failure, manual termination). This gives us HA auto-restart.
  # Application-level health check is handled by Nginx passive failover.
  health_check_type         = "EC2"
  health_check_grace_period = 600 # 10 min — cloud-init + Docker + WP init

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Scaling policies ──────────────────────────────────────────────────────────
# These allow demonstrating automatic scaling based on CPU load

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.web.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.web.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale up when CPU > 70%"
  alarm_actions       = concat([aws_autoscaling_policy.scale_up.arn], local.sns_alert_arns)

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale down when CPU < 30%"
  alarm_actions       = concat([aws_autoscaling_policy.scale_down.arn], local.sns_alert_arns)

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

# Alert when running web instances drop below the configured minimum.
# Fires when the ASG cannot replace a failed instance fast enough.
resource "aws_cloudwatch_metric_alarm" "instances_low" {
  count               = var.alert_email != "" ? 1 : 0
  alarm_name          = "${var.project_name}-instances-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = var.web_min_size
  alarm_description   = "InService web instances dropped below minimum — instance failure detected"
  alarm_actions       = local.sns_alert_arns
  ok_actions          = local.sns_alert_arns

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}
