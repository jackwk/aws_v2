# --- Knowledge Base Role ---
resource "aws_iam_role" "bedrock_kb_role" {
  name = "${var.project_prefix}-kb-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_policy" {
  name = "${var.project_prefix}-kb-policy-${var.environment}"
  role = aws_iam_role.bedrock_kb_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = ["arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"]
      },
      {
        # Access to your Glue Processed Bucket via SSM Parameter
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetObject"]
        Resource = [
          "arn:aws:s3:::${data.aws_ssm_parameter.processed_bucket.value}",
          "arn:aws:s3:::${data.aws_ssm_parameter.processed_bucket.value}/*"
        ]
      },
      {
        # Access to the new S3 Vector Bucket
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:QueryVectors", 
          "s3vectors:DeleteVectors",
          "s3vectors:GetVectors",
          "s3vectors:ListIndexes"
        ]
        Resource = [
          # Vector Bucket ARN
          "arn:aws:s3vectors:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/${var.project_prefix}-vector-store-${var.environment}",
          # Vector Index ARN
          "arn:aws:s3vectors:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/${var.project_prefix}-vector-store-${var.environment}/index/*"
        ]
      }
    ]
  })
}


# --- Agent Role ---
resource "aws_iam_role" "bedrock_agent_role" {
  name = "${var.project_prefix}-agent-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:agent/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent_policy" {
  name = "${var.project_prefix}-agent-policy-${var.environment}"
  role = aws_iam_role.bedrock_agent_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = ["arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-lite-v1:0"]
      },
      {
        Effect = "Allow"
        Action = ["bedrock:Retrieve"]
        Resource = ["arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
      },
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = ["arn:aws:bedrock:*::foundation-model/*"]
        }
    ]
  })
}