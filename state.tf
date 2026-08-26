# The bootstrap paradox: Terraform needs a state bucket, and the state bucket is Terraform's to
# create. Resolved by creating it with `aws s3api` before the first init and adopting it here —
# cleaner than committing local state, and `import` was already on the curriculum in terraform.md.
#
# On a second apply these import blocks are no-ops, so they stay in the file as the record of how
# the bucket got here.
import {
  to = aws_s3_bucket.state
  id = var.state_bucket
}

import {
  to = aws_s3_bucket_versioning.state
  id = var.state_bucket
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.state
  id = var.state_bucket
}

import {
  to = aws_s3_bucket_public_access_block.state
  id = var.state_bucket
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State accumulates a version per apply forever. Ninety days is enough to recover from a bad apply
# and short enough that the bucket does not grow without bound.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
