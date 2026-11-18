# Guardrail enforcing "no external medical advice" + basic PII/content filtering.
# The harness resource has no guardrail attribute yet, so invoke_agent.py applies it
# (bedrock-runtime ApplyGuardrail) to the user input and the final answer.
resource "aws_bedrock_guardrail" "faers" {
  name                      = "${var.project_prefix}-faers-guardrail-${var.environment}"
  description               = "Blocks personal medical advice requests"
  blocked_input_messaging   = "This assistant only analyses FAERS reports and cannot give medical advice."
  blocked_outputs_messaging = "I can't provide medical advice. Please consult a healthcare professional."

  topic_policy_config {
    topics_config {
      name       = "medical_advice"
      type       = "DENY"
      definition = "Personal medical advice, diagnosis, dosing or treatment recommendations for an individual."
      examples = [
        "Should I stop taking my medication?",
        "What dose of this drug should I take?",
        "Can I take this drug together with alcohol?"
      ]
    }
    tier_config {
      tier_name = "CLASSIC"
    }
  }

  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    tier_config {
      tier_name = "CLASSIC"
    }
  }
}

output "guardrail_id" {
  value = aws_bedrock_guardrail.faers.guardrail_id
}
