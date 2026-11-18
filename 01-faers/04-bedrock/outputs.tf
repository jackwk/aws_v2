output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.faers.id
}

output "data_source_id" {
  value = aws_bedrockagent_data_source.faers_s3.data_source_id
}

output "gateway_arn" {
  value = aws_bedrockagentcore_gateway.faers.gateway_arn
}

output "harness_arn" {
  value = aws_bedrockagentcore_harness.faers.arn
}
