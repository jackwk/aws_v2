# Ingest (Lambda) -> Process (Glue, .sync) -> Sync Knowledge Base (SDK integration + poll loop)
resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project_prefix}-faers-pipeline-${var.environment}"
  role_arn = aws_iam_role.sfn.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  definition = jsonencode({
    Comment = "FAERS: ingest -> Glue -> Knowledge Base sync"
    StartAt = "Ingest"
    States = {
      Ingest = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.ingest_function
          "Payload.$"  = "$"
        }
        ResultSelector = { "ingested.$" = "$.Payload" }
        ResultPath     = "$.ingest"
        Retry          = [{ ErrorEquals = ["States.TaskFailed"], IntervalSeconds = 5, MaxAttempts = 2, BackoffRate = 2 }]
        Catch          = [{ ErrorEquals = ["States.ALL"], Next = "IngestFailed", ResultPath = "$.error" }]
        Next           = "CheckIngest"
      }
      # Python Lambda reports errors as {statusCode: 500}; Rust Lambda has no statusCode
      # (it raises an error instead, handled by Catch above). Fail only on an explicit non-200.
      CheckIngest = {
        Type = "Choice"
        Choices = [{
          And = [
            { Variable = "$.ingest.ingested.statusCode", IsPresent = true },
            { Not = { Variable = "$.ingest.ingested.statusCode", NumericEquals = 200 } }
          ]
          Next = "IngestFailed"
        }]
        Default = "ProcessWithGlue"
      }
      IngestFailed = {
        Type  = "Fail"
        Error = "IngestFailed"
        Cause = "Ingestion Lambda returned a non-200 status"
      }
      ProcessWithGlue = {
        Type       = "Task"
        Resource   = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = { JobName = local.glue_job }
        ResultPath = null
        Next       = "StartKbSync"
      }
      StartKbSync = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:bedrockagent:startIngestionJob"
        Parameters = {
          KnowledgeBaseId = local.kb_id
          DataSourceId    = local.data_source_id
        }
        ResultSelector = { "ingestionJobId.$" = "$.IngestionJob.IngestionJobId" }
        ResultPath     = "$.kb"
        Next           = "WaitForKb"
      }
      WaitForKb = {
        Type    = "Wait"
        Seconds = 10
        Next    = "GetKbSyncStatus"
      }
      GetKbSyncStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:bedrockagent:getIngestionJob"
        Parameters = {
          KnowledgeBaseId    = local.kb_id
          DataSourceId       = local.data_source_id
          "IngestionJobId.$" = "$.kb.ingestionJobId"
        }
        ResultSelector = { "status.$" = "$.IngestionJob.Status" }
        ResultPath     = "$.kb.poll"
        Next           = "KbDone"
      }
      KbDone = {
        Type = "Choice"
        Choices = [
          { Variable = "$.kb.poll.status", StringEquals = "COMPLETE", Next = "Done" },
          { Variable = "$.kb.poll.status", StringEquals = "FAILED", Next = "KbFailed" }
        ]
        Default = "WaitForKb"
      }
      KbFailed = {
        Type  = "Fail"
        Error = "KnowledgeBaseSyncFailed"
        Cause = "Bedrock ingestion job failed"
      }
      Done = { Type = "Succeed" }
    }
  })
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${var.project_prefix}-faers-pipeline-${var.environment}"
  retention_in_days = 7
}

# Run the whole pipeline automatically on a schedule? Left disabled - start manually:
#   aws stepfunctions start-execution --state-machine-arn <arn> --input '{"limit":50,"skip":0}'
output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}
