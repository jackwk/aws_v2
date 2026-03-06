# 1. IAM Role for the Lambda to execute and write logs
resource "aws_iam_role" "lambda_exec_role" {
  name = "rust_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 1. Create a policy that allows putting objects into your specific S3 bucket
resource "aws_iam_policy" "lambda_rust_s3_write_policy" {
  name        = "${var.project_prefix}-lambda-rust-s3-write-${var.environment}"
  description = "Allows the Rust Lambda to write to the raw FAERS bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.project_prefix}-raw-faers-${var.environment}/*"
      }
    ]
  })
}

# 2. Attach this new S3 policy to your existing Lambda role
resource "aws_iam_role_policy_attachment" "lambda_s3_write_attach" {
  role       = aws_iam_role.lambda_exec_role.name # Matches the role we made earlier
  policy_arn = aws_iam_policy.lambda_rust_s3_write_policy.arn
}

resource "aws_lambda_function" "rust_function" {
  # Namespacing the function name is optional, but highly recommended
  function_name = "${var.project_prefix}-faers-rust-lambda-${var.environment}"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = "${path.module}/../app/target/lambda/faers-rust/bootstrap.zip"
  source_code_hash = filebase64sha256("${path.module}/../app/target/lambda/faers-rust/bootstrap.zip")

  runtime       = "provided.al2023"
  handler       = "rust.handler" 
  memory_size = 256 # Adjust based on your payload size
  timeout     = 60  # Increased from default 3 seconds
  architectures = ["arm64"] 

  # Inject the bucket name into the Rust runtime environment
  environment {
    variables = {
      DESTINATION_BUCKET = "${var.project_prefix}-raw-faers-${var.environment}"
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_logs_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}