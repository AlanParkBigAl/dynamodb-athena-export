variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-2" # Sydney
}

variable "project" {
  description = "Short name used as a prefix for resources. Lowercase letters, digits and hyphens only."
  type        = string
  default     = "ddb-athena-export"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project))
    error_message = "project must be 3-24 chars: lowercase letters, digits, hyphens."
  }
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "demo"
}

variable "table_name" {
  description = "Name of the DynamoDB table to create and export."
  type        = string
  default     = "Orders"
}

variable "table_deletion_protection" {
  description = "Enable DynamoDB deletion protection. Leave false for a demo you want to tear down."
  type        = bool
  default     = false
}

variable "export_schedule" {
  description = "EventBridge schedule expression (UTC). Default is 16:00 UTC daily (02:00 AEST)."
  type        = string
  default     = "cron(0 16 * * ? *)"
}

variable "export_retention_days" {
  description = "Days before old exports are expired from S3."
  type        = number
  default     = 30
}

variable "athena_scan_limit_bytes" {
  description = "Per-query data scan cutoff for the Athena workgroup (default 1 GiB)."
  type        = number
  default     = 1073741824
}

variable "force_destroy_buckets" {
  description = "Allow terraform destroy to delete non-empty buckets. Demo teardown only; keep false for real data."
  type        = bool
  default     = false
}
