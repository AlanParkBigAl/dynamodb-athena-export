# ---------------------------------------------------------------------------
# Scheduled export: EventBridge -> Lambda -> dynamodb:ExportTableToPointInTime
# The export reads from PITR backups, so it does not consume table RCUs.
# ---------------------------------------------------------------------------

data "archive_file" "export_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/export_handler.py"
  output_path = "${path.module}/build/export_handler.zip"
}

resource "aws_cloudwatch_log_group" "export_lambda" {
  name              = "/aws/lambda/${var.project}-export"
  retention_in_days = 30
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "export_lambda" {
  name               = "${var.project}-export-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Least privilege: start exports for this one table, write only under the
# exports/ prefix of the exports bucket, and write to its own log group.
data "aws_iam_policy_document" "export_lambda" {
  statement {
    sid       = "StartExport"
    actions   = ["dynamodb:ExportTableToPointInTime"]
    resources = [aws_dynamodb_table.orders.arn]
  }

  statement {
    sid = "WriteExports"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.this["exports"].arn}/${local.export_prefix}/*"]
  }

  statement {
    sid     = "Logs"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "${aws_cloudwatch_log_group.export_lambda.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "export_lambda" {
  name   = "export-permissions"
  role   = aws_iam_role.export_lambda.id
  policy = data.aws_iam_policy_document.export_lambda.json
}

resource "aws_lambda_function" "export" {
  function_name    = "${var.project}-export"
  role             = aws_iam_role.export_lambda.arn
  runtime          = "python3.12"
  handler          = "export_handler.handler"
  filename         = data.archive_file.export_lambda.output_path
  source_code_hash = data.archive_file.export_lambda.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TABLE_ARN     = aws_dynamodb_table.orders.arn
      TABLE_NAME    = aws_dynamodb_table.orders.name
      EXPORT_BUCKET = aws_s3_bucket.this["exports"].bucket
      EXPORT_PREFIX = local.export_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.export_lambda]
}

resource "aws_cloudwatch_event_rule" "export_schedule" {
  name                = "${var.project}-export-schedule"
  description         = "Triggers the DynamoDB -> S3 export"
  schedule_expression = var.export_schedule
}

resource "aws_cloudwatch_event_target" "export_lambda" {
  rule = aws_cloudwatch_event_rule.export_schedule.name
  arn  = aws_lambda_function.export.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.export.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.export_schedule.arn
}
