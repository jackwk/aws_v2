import json
import os
import urllib.request
import boto3
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Query openFDA FAERS API and save JSON response to S3.
    Expects 'limit' and 'skip' in event payload.
    """
    limit = event.get('limit', 10)
    skip = event.get('skip', 0)
    bucket_name = os.environ.get('BUCKET_NAME')
    
    # openFDA FAERS API endpoint
    url = f"https://api.fda.gov/drug/event.json?limit={limit}&skip={skip}"
    
    try:
        print(f"Fetching data from {url}")
        with urllib.request.urlopen(url) as response:
            data = json.loads(response.read().decode())
            
        # Generate a unique filename based on timestamp
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        file_name = f"raw/faers_data_{timestamp}_{skip}_{limit}.json"
        
        print(f"Uploading data to s3://{bucket_name}/{file_name}")
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data successfully ingested',
                'bucket': bucket_name,
                'key': file_name,
                'records_count': len(data.get('results', []))
            })
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
