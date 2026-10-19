variable "aws_access_key" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    sqs = "http://localhost:4566"
  }
}

resource "aws_sqs_queue" "render_queue_dlq" {
  name                      = "render-queue-dlq"
  message_retention_seconds = 1209600

  tags = {
    departamento = "render-final"
    ambiente     = "desarrollo"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_sqs_queue" "render_queue" {
  name                       = "render-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.render_queue_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    departamento = "render-final"
    ambiente     = "desarrollo"
    proyecto     = "pipeline-vfx"
  }
}