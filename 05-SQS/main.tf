provider "aws" {
  region = "us-east-2"
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