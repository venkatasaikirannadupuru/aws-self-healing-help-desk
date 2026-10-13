data "archive_file" "lambda_recovery" {
  type        = "zip"
  source_file = "${path.module}/lambda_recovery.py"
  output_path = "${path.module}/lambda_recovery.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_recovery" {
  name               = "${var.project_name}-recovery-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_recovery.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_recovery" {
  statement {
    sid    = "ReadAutoScalingAndInstanceHealth"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "elasticloadbalancing:DescribeTargetHealth"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReplaceUnhealthyGroupInstances"
    effect    = "Allow"
    actions   = ["autoscaling:TerminateInstanceInAutoScalingGroup"]
    resources = [aws_autoscaling_group.app.arn]
  }
}

resource "aws_iam_role_policy" "lambda_recovery" {
  name   = "${var.project_name}-recovery-policy"
  role   = aws_iam_role.lambda_recovery.id
  policy = data.aws_iam_policy_document.lambda_recovery.json
}

resource "aws_lambda_function" "recovery" {
  function_name    = "${var.project_name}-recovery"
  description      = "Checks ASG EC2 and ALB health, then asks ASG to replace unhealthy instances."
  role             = aws_iam_role.lambda_recovery.arn
  runtime          = "python3.12"
  handler          = "lambda_recovery.lambda_handler"
  filename         = data.archive_file.lambda_recovery.output_path
  source_code_hash = data.archive_file.lambda_recovery.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      ASG_NAME             = aws_autoscaling_group.app.name
      TARGET_GROUP_ARN     = aws_lb_target_group.app.arn
      GRACE_PERIOD_SECONDS = "300"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_recovery
  ]

  tags = {
    Name = "${var.project_name}-recovery"
  }
}

resource "aws_cloudwatch_event_rule" "recovery_schedule" {
  name                = "${var.project_name}-recovery-schedule"
  description         = "Periodically checks EC2 status and ALB target health for the Help Desk ASG."
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "recovery_lambda" {
  rule      = aws_cloudwatch_event_rule.recovery_schedule.name
  target_id = "recovery-lambda"
  arn       = aws_lambda_function.recovery.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_events" {
  statement_id  = "AllowCloudWatchEventsInvokeRecovery"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recovery.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.recovery_schedule.arn
}
