resource "aws_iam_role" "execution" {
  name = "${local.full_name}-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "execution" {
  name = "execution"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.execution_policy_statements
  })
}

resource "aws_iam_role" "task" {
  name = "${local.full_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "task" {
  count = var.task_role_policy_json != null ? 1 : 0

  name   = "application"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_json
}

resource "aws_iam_role_policy" "task_execute_command" {
  count = var.enable_execute_command ? 1 : 0

  name = "ecs-exec"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.task_exec_statement
  })
}
