output "table_name" {
  value = aws_dynamodb_table.orders.name
}

output "table_arn" {
  value = aws_dynamodb_table.orders.arn
}

output "export_bucket" {
  value = aws_s3_bucket.this["exports"].bucket
}

output "export_lambda_name" {
  value = aws_lambda_function.export.function_name
}

output "athena_workgroup" {
  value = aws_athena_workgroup.analytics.name
}

output "glue_database" {
  value = aws_glue_catalog_database.this.name
}

output "invoke_export_now" {
  description = "Run this to trigger an export without waiting for the schedule."
  value       = "aws lambda invoke --function-name ${aws_lambda_function.export.function_name} --region ${var.region} --cli-binary-format raw-in-base64-out /dev/stdout"
}
