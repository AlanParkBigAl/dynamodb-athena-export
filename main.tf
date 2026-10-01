data "aws_caller_identity" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  export_prefix = "exports"
  results_prefix = "query-results"
  glue_database = replace(var.project, "-", "_")

  # Account ID + region in the name avoids global S3 name collisions.
  buckets = {
    exports = "${var.project}-exports-${local.account_id}-${var.region}"
    results = "${var.project}-results-${local.account_id}-${var.region}"
  }
}

# ---------------------------------------------------------------------------
# Source table. PITR must be enabled for ExportTableToPointInTime to work.
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "orders" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "OrderId"

  attribute {
    name = "OrderId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = var.table_deletion_protection

  # Encrypted at rest with the default AWS-owned key (no KMS config needed).
}

# ---------------------------------------------------------------------------
# Buckets: one for exports (data lake), one for Athena query results.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = each.value
  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "tls_only" {
  for_each = aws_s3_bucket.this

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = data.aws_iam_policy_document.tls_only[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "exports" {
  bucket = aws_s3_bucket.this["exports"].id

  rule {
    id     = "expire-old-exports"
    status = "Enabled"

    filter {
      prefix = "${local.export_prefix}/"
    }

    expiration {
      days = var.export_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.this["results"].id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {
      prefix = "${local.results_prefix}/"
    }

    expiration {
      days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}