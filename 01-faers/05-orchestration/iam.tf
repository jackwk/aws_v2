resource "aws_iam_role" "sfn" {
  name = "${var.project_prefix}-sfn-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "pipeline"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = ["arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${local.ingest_function}"]
      },
      {
        Effect   = "Allow"
        Action   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
        Resource = ["arn:aws:glue:${var.aws_region}:${local.account_id}:job/${local.glue_job}"]
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:StartIngestionJob", "bedrock:GetIngestionJob"]
        Resource = ["arn:aws:bedrock:${var.aws_region}:${local.account_id}:knowledge-base/${local.kb_id}"]
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = ["*"] # required by Step Functions logging; these actions don't support resource scoping
      }
    ]
  })
}
