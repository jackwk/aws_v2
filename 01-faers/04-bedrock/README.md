# 04-bedrock

S3 Vectors + Knowledge Base + AgentCore gateway/harness (replaces Bedrock Agents Classic).

```
./invoke_agent.py "Which reports mention Letairis and what reactions were reported?"
./invoke_agent.py "What reactions were reported for TASIGNA?"
./invoke_agent.py "Should I stop taking Letairis?"        # blocked by the guardrail
./invoke_agent.py "Who made the Eiffel Tower?"            # agent should refuse: not in FAERS data
```

Expected: tool call `search_faers {"query": ...}` followed by an answer citing Report IDs and
received dates. Needs boto3 >= 1.42 (`invoke_harness`).
