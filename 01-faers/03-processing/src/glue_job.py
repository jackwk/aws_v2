import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import StringType

# Get arguments
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'RAW_BUCKET',
    'PROCESSED_BUCKET'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Paths
input_path = f"s3://{args['RAW_BUCKET']}/raw/"
output_path = f"s3://{args['PROCESSED_BUCKET']}/processed/"

# Load raw JSON data
# openFDA FAERS JSON has a top-level 'results' array
df_raw = spark.read.option("multiline", "true").json(input_path)

# Explode results if necessary or select if already parsed
if "results" in df_raw.columns:
    df = df_raw.select(F.explode("results").alias("result")).select("result.*")
else:
    df = df_raw

# Extract and format
# Sex: 1=Male, 2=Female, 0=Unknown
processed_df = df.withColumn(
    "patient_sex_desc",
    F.when(F.col("patient.patientsex") == 1, "male")
    .when(F.col("patient.patientsex") == 2, "female")
    .otherwise("unknown")
).withColumn(
    "patient_age",
    F.coalesce(F.col("patient.patientonsetage"), F.lit("unknown"))
).withColumn(
    "drugs_list",
    F.expr("transform(patient.drug, x -> x.medicinalproduct)")
).withColumn(
    "drugs_str",
    F.array_join("drugs_list", ", ")
).withColumn(
    "reactions_list",
    F.expr("transform(patient.reaction, x -> x.reactionmeddrapt)")
).withColumn(
    "reactions_str",
    F.array_join("reactions_list", ", ")
)

# Create the semantic description (Enriched for Vector RAG)
processed_df = processed_df.withColumn(
    "descriptive_text",
    F.concat(
        F.lit("Report ID "), F.col("safetyreportid"), 
        F.lit(" received on "), F.col("receivedate"), F.lit(": "),
        F.lit("A "), F.col("patient_age"), F.lit(" year old "), F.col("patient_sex_desc"),
        F.lit(" taking "), F.col("drugs_str"),
        F.lit(" reported "), F.col("reactions_str"), F.lit(".")
    )
)

# Select ONLY the text column
final_df = processed_df.select("descriptive_text")

# Output to processed S3 bucket as a raw Text file
final_df.coalesce(1).write.mode("overwrite").text(output_path)

job.commit()