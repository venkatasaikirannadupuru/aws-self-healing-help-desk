data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_ecr_repository" "app" {
  name                 = "aws-self-healing-help-desk"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = { Name = "${var.project_name}-ecr" }
}
resource "aws_lb" "app" {
  name               = "helpdesk-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = { Name = "${var.project_name}-alb" }
}
resource "aws_lb_target_group" "app" {
  name        = "helpdesk-${var.environment}-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = { Name = "${var.project_name}-tg" }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region = var.aws_region
    ecr_url    = aws_ecr_repository.app.repository_url
    image_tag  = var.image_tag
  }))
  update_default_version = true
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-app" }
  }
  depends_on = [aws_iam_role_policy_attachment.ecr_read_only]
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_name}-asg"
  min_size                  = 0
  max_size                  = 2
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = aws_subnet.public[*].id
  health_check_type         = "ELB"
  health_check_grace_period = 240
  target_group_arns         = [aws_lb_target_group.app.arn]
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  depends_on = [aws_lb_listener.http]
  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }
}
