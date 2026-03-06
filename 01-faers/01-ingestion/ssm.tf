resource "aws_ssm_parameter" "raw_bucket_name" {
  name  = "/${var.project_prefix}/${var.environment}/raw_bucket"
  type  = "String"
  value = aws_s3_bucket.raw_data.id

  tags = {
    Environment = var.environment
  }
}
