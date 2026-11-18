#!/usr/bin/env python3
"""Ask the FAERS AgentCore harness a question.  Usage: ./invoke_agent.py "question" """
import subprocess, sys, uuid, json, boto3

arn = subprocess.check_output(["terraform", "output", "-raw", "harness_arn"], text=True).strip()
region = arn.split(":")[3]
client = boto3.client("bedrock-agentcore", region_name=region)
q = " ".join(sys.argv[1:]) or "Which reports mention Letairis and what reactions were reported?"

resp = client.invoke_harness(
    harnessArn=arn,
    runtimeSessionId=str(uuid.uuid4()),  # must be >= 33 chars
    messages=[{"role": "user", "content": [{"text": q}]}],
)
for ev in resp["stream"]:
    d = ev.get("contentBlockDelta", {}).get("delta", {})
    if "text" in d:
        print(d["text"], end="", flush=True)
    elif "toolUse" in d:
        pass
print()
