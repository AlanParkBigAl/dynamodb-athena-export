"""Start a full DynamoDB table export to S3 from point-in-time recovery.

Triggered daily by EventBridge. The export reads from PITR backups, so it does
not consume the table's read capacity.

Output layout (one folder per UTC day, matching the Glue partition projection):
    s3://<bucket>/<prefix>/<table>/export_date=YYYY-MM-DD/AWSDynamoDB/<export-id>/data/*.json.gz
"""

import datetime
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.client("dynamodb")


def handler(event, context):
    table_arn = os.environ["TABLE_ARN"]
    table_name = os.environ["TABLE_NAME"]
    bucket = os.environ["EXPORT_BUCKET"]
    prefix_root = os.environ["EXPORT_PREFIX"].strip("/")

    now = datetime.datetime.now(datetime.timezone.utc)
    export_date = now.strftime("%Y-%m-%d")
    s3_prefix = f"{prefix_root}/{table_name}/export_date={export_date}"

    logger.info("Starting export of %s to s3://%s/%s", table_arn, bucket, s3_prefix)

    response = dynamodb.export_table_to_point_in_time(
        TableArn=table_arn,
        ExportTime=now,
        S3Bucket=bucket,
        S3Prefix=s3_prefix,
        S3SseAlgorithm="AES256",
        ExportFormat="DYNAMODB_JSON",
        # Makes accidental double-invocations within the same day idempotent.
        ClientToken=f"{table_name}-{export_date}",
    )

    description = response["ExportDescription"]
    result = {
        "exportArn": description["ExportArn"],
        "exportStatus": description["ExportStatus"],
        "s3Prefix": s3_prefix,
    }
    logger.info("Export started: %s", json.dumps(result))
    return result
