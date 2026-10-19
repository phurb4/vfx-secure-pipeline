resource "aws_s3_bucket" "input" {
  bucket = "vfx-${var.departamento}-input"

  tags = {
    departamento = var.departamento
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_s3_bucket_versioning" "input_versioning" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "input_encryption" {
  bucket = aws_s3_bucket.input.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "input_block" {
  bucket                  = aws_s3_bucket.input.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "output" {
  bucket = "vfx-${var.departamento}-output"

  tags = {
    departamento = var.departamento
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_s3_bucket_versioning" "output_versioning" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output_encryption" {
  bucket = aws_s3_bucket.output.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "output_block" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}