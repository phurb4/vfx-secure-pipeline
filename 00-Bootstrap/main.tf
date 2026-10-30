provider "aws" {
  region = "us-east-2"
}

data "aws_caller_identity" "current" {}

locals {
  bucket_estado = "vfx-tfstate-a7k3"
}

# BUCKET DE ESTADO

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_estado

  tags = {
    proyecto = "pipeline-vfx"
    uso      = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "tfstate_versioning" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_sse" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_block" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# POLITICA DEL BUCKET: solo el rol vfx-admin-role puede borrar o cambiar reglas.
# En una sesion de rol, aws:PrincipalArn trae el ARN del ROL (no el de la sesion).
# El usuario vfx-admin y su politica NO se crean aca: ya existen a mano en la cuenta.

data "aws_iam_policy_document" "tfstate_bucket_policy" {
  statement {
    sid    = "SoloAdminBorraOCambiaReglas"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning",
    ]

    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/vfx-admin-role"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate_policy" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.tfstate_block]
}