# FAERS demo: ingest → process → vector KB → agent

Branch: `improvements`. Each folder is a separate Terraform stack, deployed in order.
Shared inputs: `-var project_prefix=v1 -var environment=dev` (region `eu-central-1`).

| Folder | What it shows |
|---|---|
| `01-ingestion` | S3 raw bucket + Python Lambda calling openFDA, SSM parameter with bucket name |
| `02-lambda-rust` | Same ingestion in Rust on arm64 (`provided.al2023`). Stack is in `infra/`, code in `app/` |
| `03-processing` | Glue job turning raw JSON into text for embedding, processed bucket |
| `04-bedrock` | S3 Vectors bucket/index, Knowledge Base, data source + sync, retrieval Lambda, AgentCore gateway + harness (replaces Bedrock Agents Classic), Guardrail |
| `05-orchestration` | Step Functions: ingest Lambda → Glue → KB sync |

## Current state (end of day 1)
- Everything was deployed, tested end to end and **destroyed** again. The account is clean.
- Verified: both state machine variants (`ingest_lambda=python` / `rust`) succeed; the agent answers with
  Report IDs and dates; the guardrail blocks medical-advice questions.
- Not done / ideas: root Makefile + shared tfvars for one-command deploy; the guardrail is applied
  client-side in `invoke_agent.py` (harness has no guardrail attribute yet); `local-exec` ingestion
  trigger in `04-bedrock` is now redundant with `05-orchestration`; `00-ssm` and
  `03-rust-ec2-template` are untouched and not renumbered. Terraform state stays local (decided to skip S3/DynamoDB backend).

## Manual test
Prereqs: AWS credentials, Terraform >= 1.5, `cargo-lambda` (for the Rust Lambda), Python 3.10+ with boto3 >= 1.42.

```bash
V="-var project_prefix=v1 -var environment=dev"
cd 01-faers

# 1. Ingestion + processing
(cd 01-ingestion  && terraform init && terraform apply $V)
# 02-lambda-rust: build first (output: app/target/lambda/faers-rust/bootstrap.zip), then apply
(cd 02-lambda-rust/app && cargo lambda build --release --arm64 --output-format zip)
(cd 02-lambda-rust/infra && terraform init && terraform apply $V)
(cd 03-processing && terraform init && terraform apply $V)

# 2. Bedrock (the harness takes ~4-5 min to create)
(cd 04-bedrock && terraform init && terraform apply $V)

# 3. Orchestration
(cd 05-orchestration && terraform init && terraform apply $V)      # add -var ingest_lambda=rust for the Rust path
```

Run the pipeline (loads data, runs Glue, syncs the KB; a few minutes):
```bash
cd 05-orchestration
aws stepfunctions start-execution --region eu-central-1 \
  --state-machine-arn $(terraform output -raw state_machine_arn) \
  --input '{"limit":20,"skip":0}'
```
Watch it in the Step Functions console or with `aws stepfunctions describe-execution`.

Ask the agent (use a venv with a recent boto3; system Python may lack it):
```bash
cd 04-bedrock
python3 -m venv .venv && .venv/bin/pip install -U boto3
.venv/bin/python invoke_agent.py "Which reports mention Letairis and what reactions were reported?"
.venv/bin/python invoke_agent.py "Should I stop taking Letairis?"   # blocked by guardrail
```
Expected: `[tool call] search_faers {...}` then an answer citing Report IDs and received dates.

## Gotchas
- Nova v1 Lite/Pro fail tool calls in the harness; default is `eu.amazon.nova-2-lite-v1:0` (`-var agent_model_id=...`).
- Re-sync the KB after new data: rerun the state machine (or `terraform apply -replace=terraform_data.ingest` in `04-bedrock`).
- `05-orchestration` needs `04-bedrock` applied first (reads KB/data source IDs from SSM).

## Teardown (reverse order)
```bash
for d in 05-orchestration 04-bedrock 03-processing 02-lambda-rust/infra 01-ingestion; do
  (cd $d && terraform destroy $V)
done
```
`02-lambda-rust/infra` destroy was slow (>10 min) last time.
