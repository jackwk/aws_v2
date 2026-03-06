variable "knowledge_base_id" {
  description = "The ID of the S3 Vector Knowledge Base created via CLI"
  type        = string
}

# 1. Create the Claude-Powered Agent
resource "aws_bedrockagent_agent" "faers_agent" {
  agent_name              = "${var.project_prefix}-pharma-agent-${var.environment}"
  
  # Reference the resource directly from your iam.tf file!
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  foundation_model        = "anthropic.claude-3-haiku-20240307-v1:0"
  
  instruction             = "You are a pharmacovigilance specialist. Your task is to analyze adverse drug reactions based strictly on the FAERS data provided in your knowledge base. When discussing a case, you must cite the Report ID and received date. Do not provide external medical advice."

  # Ensure the policy is attached before the Agent is created
  depends_on = [aws_iam_role_policy.bedrock_agent_policy]
}

# 2. Attach the Agent to your CLI-created Knowledge Base
resource "aws_bedrockagent_agent_knowledge_base_association" "kb_link" {
  agent_id             = aws_bedrockagent_agent.faers_agent.id
  agent_version        = "DRAFT"
  knowledge_base_id    = var.knowledge_base_id 
  knowledge_base_state = "ENABLED"
  description          = "FAERS semantic data for adverse event querying."
}

# 3. Create the Data Source (Telling the KB to read your Glue bucket)
resource "aws_bedrockagent_data_source" "faers_s3_source" {
  knowledge_base_id = var.knowledge_base_id
  name              = "${var.project_prefix}-faers-source-${var.environment}"
  
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = "arn:aws:s3:::${data.aws_ssm_parameter.processed_bucket.value}"
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

# Output the Data Source ID so we can trigger the sync in the next step
output "data_source_id" {
  value = aws_bedrockagent_data_source.faers_s3_source.data_source_id
}