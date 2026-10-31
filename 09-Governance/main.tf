provider "aws" {
  region = "us-east-2"
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    proyecto     = "pipeline-vfx"
    departamento = "gobernanza"
    ambiente     = "desarrollo"
  }
}

# --- Bucket donde AWS Config guarda sus registros ---

resource "aws_s3_bucket" "config_logs" {
  bucket = "vfx-config-logs"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  bucket                  = aws_s3_bucket.config_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Politica que AWS exige para que Config pueda escribir en el bucket
resource "aws_s3_bucket_policy" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config_logs.arn
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.config_logs.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

# --- Rol IAM que usa Config ---

resource "aws_iam_role" "config" {
  name = "vfx-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "config_s3" {
  name = "vfx-config-s3-policy"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetBucketAcl"]
        Resource = [
          aws_s3_bucket.config_logs.arn,
          "${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        ]
      },
      {
        Sid      = "ConfigReadS3Configuration"
        Effect   = "Allow"
        Action   = ["s3:Get*", "s3:ListAllMyBuckets"]
        Resource = "*"
      }
    ]
  })
}

# --- Recorder, canal de entrega y encendido ---

resource "aws_config_configuration_recorder" "main" {
  name     = "vfx-config-recorder"
  role_arn = aws_iam_role.config.arn

  # Solo buckets de S3: es lo unico que evaluan las 3 reglas de abajo
  recording_group {
    all_supported = false
    resource_types = ["AWS::S3::Bucket"]
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "vfx-config-channel"
  s3_bucket_name = aws_s3_bucket.config_logs.id

  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config_logs,
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# --- Reglas de cumplimiento (reglas administradas por AWS) ---

resource "aws_config_config_rule" "s3_public_read_prohibited" {
  name = "vfx-s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "s3_encryption_enabled" {
  name = "vfx-s3-bucket-server-side-encryption-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "s3_versioning_enabled" {
  name = "vfx-s3-bucket-versioning-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_VERSIONING_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}
# --- GuardDuty: NO desplegado en la cuenta real ---
# La SCP de la Organizacion niega guardduty:CreateDetector (verificado el
# 30 de octubre de 2026). En una cuenta sin esa restriccion se agrega:
#
# resource "aws_guardduty_detector" "main" {
#   enable                       = true
#   finding_publishing_frequency = "FIFTEEN_MINUTES"
#   tags                         = local.common_tags
# }
#
# resource "aws_guardduty_detector_feature" "s3_data_events" {
#   detector_id = aws_guardduty_detector.main.id
#   name        = "S3_DATA_EVENTS"
#   status      = "ENABLED"
# }