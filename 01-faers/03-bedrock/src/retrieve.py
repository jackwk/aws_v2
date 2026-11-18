import os
import boto3

client = boto3.client("bedrock-agent-runtime")
KB_ID = os.environ["KNOWLEDGE_BASE_ID"]


def lambda_handler(event, context):
    """AgentCore Gateway Lambda target: event is the tool input arguments."""
    query = event["query"]
    top_k = int(event.get("top_k", 5))
    resp = client.retrieve(
        knowledgeBaseId=KB_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": top_k}},
    )
    return {
        "results": [
            {
                "text": r["content"]["text"],
                "score": r.get("score"),
                "source": r.get("location", {}).get("s3Location", {}).get("uri"),
            }
            for r in resp["retrievalResults"]
        ]
    }
