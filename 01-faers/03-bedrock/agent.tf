# Replacement for the (maintenance-mode) Bedrock Agents Classic agent:
# KB -> Lambda (Retrieve) -> AgentCore Gateway (MCP tool) -> AgentCore harness

data "archive_file" "retrieve" {
  type        = "zip"
  source_file = "${path.module}/src/retrieve.py"
  output_path = "${path.module}/retrieve.zip"
}

resource "aws_lambda_function" "retrieve" {
  function_name    = "${var.project_prefix}-kb-retrieve-${var.environment}"
  role             = aws_iam_role.retrieve_lambda.arn
  handler          = "retrieve.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.retrieve.output_path
  source_code_hash = data.archive_file.retrieve.output_base64sha256

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.faers.id
    }
  }
}

resource "aws_bedrockagentcore_gateway" "faers" {
  name            = "${var.project_prefix}-faers-gw-${var.environment}"
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
}

resource "aws_bedrockagentcore_gateway_target" "kb_search" {
  name               = "faers-kb"
  gateway_identifier = aws_bedrockagentcore_gateway.faers.gateway_id
  description        = "Semantic search over FAERS adverse event reports"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.retrieve.arn

        tool_schema {
          inline_payload {
            name        = "search_faers"
            description = "Semantic search over FAERS adverse event reports. Returns report text with source."

            input_schema {
              type = "object"

              property {
                name        = "query"
                type        = "string"
                description = "Natural language question, e.g. drug names or reactions"
                required    = true
              }
              property {
                name        = "top_k"
                type        = "integer"
                description = "Number of passages to return (default 5)"
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_harness" "faers" {
  harness_name       = "${var.project_prefix}_pharma_agent_${var.environment}"
  execution_role_arn = aws_iam_role.harness.arn

  model {
    bedrock_model_config {
      model_id = var.agent_model_id
    }
  }

  system_prompt {
    text = "You are a pharmacovigilance specialist. Your task is to analyze adverse drug reactions based strictly on the FAERS data returned by the search_faers tool. When discussing a case, you must cite the Report ID and received date. Do not provide external medical advice."
  }

  tool {
    type = "agentcore_gateway"
    name = "faers"
    config {
      agentcore_gateway {
        gateway_arn = aws_bedrockagentcore_gateway.faers.gateway_arn
        outbound_auth {
          aws_iam = true
        }
      }
    }
  }

  depends_on = [aws_iam_role_policy.harness, aws_bedrockagentcore_gateway_target.kb_search]
}
