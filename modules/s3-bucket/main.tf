data "aws_caller_identity" "current" {}

locals {
  bucket_name = join("-", compact([
    var.name,
    var.environment,
    var.name_suffix,
    var.append_account_id ? data.aws_caller_identity.current.account_id : "",
  ]))

  object_lock_enabled = var.object_lock_retention_days != null

  deny_insecure_transport = {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }

  cloudfront_read = var.cloudfront_distribution_arn == null ? [] : [{
    Sid       = "CloudFrontReadsObjects"
    Effect    = "Allow"
    Principal = { Service = "cloudfront.amazonaws.com" }
    Action    = "s3:GetObject"
    Resource  = "${aws_s3_bucket.this.arn}/*"
    Condition = { StringEquals = { "AWS:SourceArn" = var.cloudfront_distribution_arn } }
  }]
}

resource "aws_s3_bucket" "this" {
  bucket              = local.bucket_name
  object_lock_enabled = local.object_lock_enabled

  tags = merge(var.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count  = local.object_lock_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "tidy"
    status = "Enabled"

    filter {}

    dynamic "noncurrent_version_expiration" {
      for_each = local.object_lock_enabled ? [] : [1]

      content {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat([local.deny_insecure_transport], local.cloudfront_read)
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}
