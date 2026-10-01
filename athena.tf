# ---------------------------------------------------------------------------
# Query layer: Glue table over the export files + a cost-capped Athena workgroup.
#
# Exports land at:
#   s3://<bucket>/exports/<table>/export_date=YYYY-MM-DD/AWSDynamoDB/<id>/data/*.json.gz
#
# export_date is a partition column resolved with partition projection, so no
# crawler or MSCK REPAIR is needed. Always filter on export_date to limit scans.
# ---------------------------------------------------------------------------

locals {
  # DYNAMODB_JSON wraps every value in a type descriptor: {"S": "..."} / {"N": "..."}.
  # Add columns here as your table's attributes grow.
  item_struct = join(",", [
    "OrderId:struct<S:string>",
    "CustomerId:struct<S:string>",
    "Status:struct<S:string>",
    "OrderTotal:struct<N:string>",
    "CreatedAt:struct<S:string>",
  ])

  table_location = "s3://${aws_s3_bucket.this["exports"].bucket}/${local.export_prefix}/${var.table_name}/"
}

resource "aws_glue_catalog_database" "this" {
  name = local.glue_database
}

resource "aws_glue_catalog_table" "orders" {
  name          = "orders"
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                        = "TRUE"
    classification                  = "json"
    "projection.enabled"            = "true"
    "projection.export_date.type"   = "date"
    "projection.export_date.format" = "yyyy-MM-dd"
    "projection.export_date.range"  = "2026-01-01,NOW"
    "projection.export_date.interval"      = "1"
    "projection.export_date.interval.unit" = "DAYS"
    "storage.location.template"     = "${local.table_location}export_date=$${export_date}/"
  }

  partition_keys {
    name = "export_date"
    type = "string"
  }

  storage_descriptor {
    location      = local.table_location
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      parameters = {
        # Export folders also contain manifest files; skip lines that don't parse.
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "item"
      type = "struct<${local.item_struct}>"
    }
  }
}

resource "aws_athena_workgroup" "analytics" {
  name          = var.project
  force_destroy = true # workgroup holds no data; safe to remove with its query history

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_scan_limit_bytes

    result_configuration {
      output_location = "s3://${aws_s3_bucket.this["results"].bucket}/${local.results_prefix}/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Saved queries (visible in the Athena console under "Saved queries").
# Replace the example dates with a day that has an export.
# ---------------------------------------------------------------------------
resource "aws_athena_named_query" "revenue_by_status" {
  name      = "orders-revenue-by-status"
  workgroup = aws_athena_workgroup.analytics.id
  database  = aws_glue_catalog_database.this.name
  query     = <<-SQL
    -- Revenue and order count per status for one export snapshot
    SELECT item.status.s                             AS status,
           COUNT(*)                                  AS orders,
           ROUND(SUM(CAST(item.ordertotal.n AS DOUBLE)), 2) AS revenue
    FROM   orders
    WHERE  export_date = '2026-10-01'
      AND  item IS NOT NULL
    GROUP  BY item.status.s
    ORDER  BY revenue DESC;
  SQL
}

resource "aws_athena_named_query" "top_customers" {
  name      = "orders-top-customers"
  workgroup = aws_athena_workgroup.analytics.id
  database  = aws_glue_catalog_database.this.name
  query     = <<-SQL
    -- Top 10 customers by spend in one export snapshot
    SELECT item.customerid.s                         AS customer_id,
           COUNT(*)                                  AS orders,
           ROUND(SUM(CAST(item.ordertotal.n AS DOUBLE)), 2) AS total_spend
    FROM   orders
    WHERE  export_date = '2026-10-01'
      AND  item IS NOT NULL
    GROUP  BY item.customerid.s
    ORDER  BY total_spend DESC
    LIMIT  10;
  SQL
}

resource "aws_athena_named_query" "snapshot_growth" {
  name      = "orders-snapshot-growth"
  workgroup = aws_athena_workgroup.analytics.id
  database  = aws_glue_catalog_database.this.name
  query     = <<-SQL
    -- Row count per daily snapshot (shows table growth over time)
    SELECT export_date,
           COUNT(*) AS orders
    FROM   orders
    WHERE  export_date BETWEEN '2026-10-01' AND '2026-10-31'
      AND  item IS NOT NULL
    GROUP  BY export_date
    ORDER  BY export_date;
  SQL
}
