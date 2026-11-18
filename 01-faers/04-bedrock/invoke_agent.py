#!/usr/bin/env python3
"""Ask the FAERS AgentCore harness a question.

Usage: ./invoke_agent.py "question"
Shows the tool calls the agent makes and applies the Bedrock guardrail to input and output.
"""
import json, subprocess, sys, uuid
import boto3


def tf(name):
    return subprocess.check_output(["terraform", "output", "-raw", name], text=True).strip()


arn, gr_id = tf("harness_arn"), tf("guardrail_id")
region = arn.split(":")[3]
agentcore = boto3.client("bedrock-agentcore", region_name=region)
runtime = boto3.client("bedrock-runtime", region_name=region)
q = " ".join(sys.argv[1:]) or "Which reports mention Letairis and what reactions were reported?"


def guard(text, source):
    r = runtime.apply_guardrail(guardrailIdentifier=gr_id, guardrailVersion="DRAFT", source=source,
                                content=[{"text": {"text": text}}])
    blocked = r["action"] == "GUARDRAIL_INTERVENED"
    return blocked, (r["outputs"][0]["text"] if blocked and r.get("outputs") else text)


blocked, msg = guard(q, "INPUT")
if blocked:
    print(f"[guardrail blocked input] {msg}")
    sys.exit(0)

resp = agentcore.invoke_harness(
    harnessArn=arn,
    runtimeSessionId=str(uuid.uuid4()),  # must be >= 33 chars
    messages=[{"role": "user", "content": [{"text": q}]}],
)

answer, tool_json, in_tool = [], "", False
for ev in resp["stream"]:
    if "contentBlockStart" in ev:
        tu = ev["contentBlockStart"].get("start", {}).get("toolUse")
        if tu:
            in_tool, tool_json = True, ""
            print(f"\n[tool call] {tu.get('name')}", end="")
    d = ev.get("contentBlockDelta", {}).get("delta", {})
    if "toolUse" in d:
        tool_json += d["toolUse"].get("input", "")
    elif "text" in d:
        answer.append(d["text"])
    if "contentBlockStop" in ev and in_tool:
        print(f" {tool_json}")
        in_tool = False

text = "".join(answer)
blocked, text = guard(text, "OUTPUT")
print("\n[guardrail blocked output]" if blocked else "\n--- answer ---")
print(text)
