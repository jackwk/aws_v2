data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "ingest_faers" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_prefix}-ingest-faers-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.raw_data.id
    }
  }
}
