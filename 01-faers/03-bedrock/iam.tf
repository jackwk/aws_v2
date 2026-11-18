# --- Knowledge Base role ---
resource "aws_iam_role" "bedrock_kb_role" {
  name = "${var.project_prefix}-kb-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${local.account_id}:knowledge-base/*" }
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
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = [local.embedding_model]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetObject"]
        Resource = [
          "arn:aws:s3:::${local.processed_bucket}",
          "arn:aws:s3:::${local.processed_bucket}/*"
        ]
        Condition = { StringEquals = { "aws:ResourceAccount" = local.account_id } }
      },
      {
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetIndex"
        ]
        Resource = [aws_s3vectors_index.faers.index_arn]
      }
    ]
  })
}

# --- Retrieval Lambda role (used behind the AgentCore gateway) ---
resource "aws_iam_role" "retrieve_lambda" {
  name = "${var.project_prefix}-kb-retrieve-lambda-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "retrieve_lambda_logs" {
  role       = aws_iam_role.retrieve_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "retrieve_lambda_kb" {
  name = "kb-retrieve"
  role = aws_iam_role.retrieve_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:Retrieve"]
      Resource = [aws_bedrockagent_knowledge_base.faers.arn]
    }]
  })
}

# --- AgentCore gateway role ---
data "aws_iam_policy_document" "agentcore_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "gateway" {
  name               = "${var.project_prefix}-agentcore-gateway-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume.json
}

resource "aws_iam_role_policy" "gateway_invoke_lambda" {
  name = "invoke-retrieve-lambda"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.retrieve.arn]
    }]
  })
}

# --- AgentCore harness execution role ---
resource "aws_iam_role" "harness" {
  name               = "${var.project_prefix}-agentcore-harness-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume.json
}

resource "aws_iam_role_policy" "harness" {
  name = "harness-policy"
  role = aws_iam_role.harness.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = ["*"] # inference profile + underlying foundation models in several EU regions
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeGateway"]
        Resource = [aws_bedrockagentcore_gateway.faers.gateway_arn]
      }
      , {
        # Harness enables short-term memory by default
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateEvent",
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:GetEvent",
          "bedrock-agentcore:ListSessions",
          "bedrock-agentcore:RetrieveMemoryRecords",
          "bedrock-agentcore:ListMemoryRecords",
          "bedrock-agentcore:GetMemoryRecord"
        ]
        Resource = ["arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:memory/*"]
      }
    ]
  })
}
