resource "aws_ssm_parameter" "processed_bucket_name" {
  name  = "/${var.project_prefix}/${var.environment}/processed_bucket"
  type  = "String"
  value = aws_s3_bucket.processed_data.id

  tags = {
    Environment = var.environment
  }
}
