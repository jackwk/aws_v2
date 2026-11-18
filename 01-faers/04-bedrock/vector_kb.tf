# --- S3 Vectors store (previously created manually) ---
resource "aws_s3vectors_vector_bucket" "faers" {
  vector_bucket_name = "${var.project_prefix}-vector-store-${var.environment}"
  force_destroy      = true
}

resource "aws_s3vectors_index" "faers" {
  index_name         = "faers-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.faers.vector_bucket_name
  data_type          = "float32"
  dimension          = 1024 # Titan Text Embeddings v2
  distance_metric    = "cosine"

  metadata_configuration {
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT"]
  }
}

# --- Knowledge Base ---
resource "aws_bedrockagent_knowledge_base" "faers" {
  name     = "${var.project_prefix}-faers-kb-${var.environment}"
  role_arn = aws_iam_role.bedrock_kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = local.embedding_model
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.faers.index_arn
    }
  }

  depends_on = [aws_iam_role_policy.bedrock_kb_policy]
}

# --- Data source: the Glue "processed" bucket ---
resource "aws_bedrockagent_data_source" "faers_s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.faers.id
  name              = "${var.project_prefix}-faers-source-${var.environment}"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = "arn:aws:s3:::${local.processed_bucket}"
      inclusion_prefixes = ["processed/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 512
        overlap_percentage = 20
      }
    }
  }
}

# --- Kick off ingestion (sync) automatically ---
# Re-runs when the data source or KB changes; run `terraform apply -replace=terraform_data.ingest`
# to re-sync after the Glue job produced new data.
resource "terraform_data" "ingest" {
  triggers_replace = [aws_bedrockagent_data_source.faers_s3.id]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      JOB=$(aws bedrock-agent start-ingestion-job --region ${var.aws_region} \
        --knowledge-base-id ${aws_bedrockagent_knowledge_base.faers.id} \
        --data-source-id ${aws_bedrockagent_data_source.faers_s3.data_source_id} \
        --query ingestionJob.ingestionJobId --output text)
      for i in $(seq 1 60); do
        S=$(aws bedrock-agent get-ingestion-job --region ${var.aws_region} \
          --knowledge-base-id ${aws_bedrockagent_knowledge_base.faers.id} \
          --data-source-id ${aws_bedrockagent_data_source.faers_s3.data_source_id} \
          --ingestion-job-id $JOB --query ingestionJob.status --output text)
        echo "ingestion: $S"
        [ "$S" = "COMPLETE" ] && exit 0
        [ "$S" = "FAILED" ] && exit 1
        sleep 10
      done
      exit 1
    EOT
  }
}

# Publish IDs via SSM so 05-orchestration can find them (same pattern as 01 -> 02)
resource "aws_ssm_parameter" "kb_id" {
  name  = "/${var.project_prefix}/${var.environment}/knowledge_base_id"
  type  = "String"
  value = aws_bedrockagent_knowledge_base.faers.id
}

resource "aws_ssm_parameter" "data_source_id" {
  name  = "/${var.project_prefix}/${var.environment}/data_source_id"
  type  = "String"
  value = aws_bedrockagent_data_source.faers_s3.data_source_id
}
