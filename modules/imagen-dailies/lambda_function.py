import os
import urllib.parse
import boto3

s3 = boto3.client("s3", endpoint_url="http://localhost.floci.io:4566")

DAILIES_BUCKET = os.environ["DAILIES_BUCKET"]
DEPT_PREFIX = os.environ["DEPT_PREFIX"]


def lambda_handler(event, context):
    record = event["Records"][0]
    src_bucket = record["s3"]["bucket"]["name"]
    src_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

    nombre_archivo = os.path.basename(src_key)
    dst_key = f"{DEPT_PREFIX}/{nombre_archivo}"

    s3.copy_object(
        CopySource={"Bucket": src_bucket, "Key": src_key},
        Bucket=DAILIES_BUCKET,
        Key=dst_key,
    )

    return {
        "statusCode": 200,
        "mensaje": f"Copiado OK: {src_key} -> {DAILIES_BUCKET}/{dst_key}",
    }