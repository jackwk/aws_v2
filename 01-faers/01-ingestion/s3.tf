resource "aws_s3_bucket" "raw_data" {
  bucket = "${var.project_prefix}-raw-faers-${var.environment}"

  force_destroy = true

  tags = {
    Name        = "Raw FAERS Data Bucket"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
