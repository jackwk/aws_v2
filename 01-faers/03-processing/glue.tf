resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_assets.id
  key    = "scripts/glue_job.py"
  source = "${path.module}/src/glue_job.py"
  etag   = filemd5("${path.module}/src/glue_job.py")
}

resource "aws_glue_job" "faers_processing" {
  name     = "${var.project_prefix}-faers-processing-${var.environment}"
  role_arn = aws_iam_role.glue_service_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_assets.id}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--RAW_BUCKET"                       = data.aws_ssm_parameter.raw_bucket.value
    "--PROCESSED_BUCKET"                 = aws_s3_bucket.processed_data.id
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_assets.id}/temp/"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
  }

  max_capacity = 2.0
  timeout      = 2880
}
