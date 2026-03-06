use aws_config::BehaviorVersion;
use aws_sdk_s3::{Client as S3Client, primitives::ByteStream}; // FIX: Imported ByteStream
use chrono::Utc;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::env;

// Define the incoming event payload
#[derive(Deserialize)]
struct Request {
    #[serde(default = "default_limit")]
    limit: u32,
    #[serde(default = "default_skip")]
    skip: u32,
}

fn default_limit() -> u32 { 10 }
fn default_skip() -> u32 { 0 }

// Define the response payload
#[derive(Serialize)]
struct Response {
    message: String,
    bucket: String,
    key: String,
    records_count: usize,
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    // 1. Initialization (Runs ONCE per container lifecycle)
    
    // FIX: Modern way to load AWS config
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let s3_client = S3Client::new(&config);
    
    let bucket_name = env::var("DESTINATION_BUCKET")
        .expect("DESTINATION_BUCKET environment variable must be set");

    // 2. Start the runtime
    // FIX: Clone the client and string for the 'static closure boundary
    lambda_runtime::run(service_fn(move |event: LambdaEvent<Request>| {
        let s3_client = s3_client.clone();
        let bucket_name = bucket_name.clone();
        
        async move {
            function_handler(&s3_client, &bucket_name, event).await
        }
    })).await
}

async fn function_handler(
    s3_client: &S3Client, 
    bucket_name: &str, 
    event: LambdaEvent<Request>
) -> Result<Response, Error> {
    let limit = event.payload.limit;
    let skip = event.payload.skip;
    
    println!("Writing to bucket: {}", bucket_name);

    // FIX: Construct the actual URL using your skip and limit payloads!
    // (Assuming this is the openFDA endpoint you are hitting)
    let url = format!(
        "https://api.fda.gov/drug/event.json?limit={}&skip={}", 
        limit, skip
    );

    // Fetch data using reqwest
    let res = reqwest::get(&url).await?.json::<Value>().await?;

    let timestamp = Utc::now().format("%Y%m%d%H%M%S").to_string();
    let file_name = format!("raw/faers_data_{}_{}_{}.json", timestamp, skip, limit);

    println!("Uploading data to s3://{}/{}", bucket_name, file_name);

    let data_string = serde_json::to_string(&res)?;

  // Upload to S3
    match s3_client
        .put_object()
        .bucket(bucket_name)
        .key(&file_name)
        .body(aws_sdk_s3::primitives::ByteStream::from(data_string.into_bytes()))
        .content_type("application/json")
        .send()
        .await 
    {
        Ok(_) => println!("Successfully uploaded to S3!"),
        Err(e) => {
            // This will print the exact AWS API error (e.g., 403 Access Denied, 404 Not Found)
            eprintln!("CRITICAL S3 ERROR: {:#?}", e); 
            return Err(e.into());
        }
    }

    // --- YOU JUST NEED TO ADD THIS BACK IN! ---

    // Count records if the "results" array exists
    let records_count = res.get("results")
        .and_then(|r| r.as_array())
        .map(|a| a.len())
        .unwrap_or(0);

    Ok(Response {
        message: "Data successfully ingested".to_string(),
        bucket: bucket_name.to_string(), 
        key: file_name,
        records_count,
    })
} 