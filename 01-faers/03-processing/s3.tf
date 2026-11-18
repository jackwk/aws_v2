resource "aws_s3_bucket" "processed_data" {
  bucket = "${var.project_prefix}-processed-faers-${var.environment}"

  force_destroy = true

  tags = {
    Name        = "Processed FAERS Data Bucket"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "glue_assets" {
  bucket = "${var.project_prefix}-glue-assets-${var.environment}"

  force_destroy = true

  tags = {
    Name        = "Glue Assets Bucket"
    Environment = var.environment
  }
}
