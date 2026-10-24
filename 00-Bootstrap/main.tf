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
    s3  = "http://localhost:4566"
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

# Requisito: 03-Cognito ya aplicado, porque los grupos se leen, no se crean aca.

data "aws_caller_identity" "current" {}

locals {
  grupos_lectores = [
    "vfx-artista",
    "vfx-lead",
    "vfx-supervisor-departamento",
    "vfx-supervisor-vfx-general",
  ]
}

# USUARIO ADMINISTRADOR DEL ESTADO

resource "aws_iam_user" "vfx_admin" {
  name = "vfx-admin"

  tags = {
    proyecto = "pipeline-vfx"
    rol      = "administrador-estado-terraform"
  }
}

# BUCKET DE ESTADO

resource "aws_s3_bucket" "tfstate" {
  bucket = "vfx-tfstate"

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

# POLITICA DEL BUCKET: solo vfx-admin puede borrar o cambiar reglas

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
      values   = [aws_iam_user.vfx_admin.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate_policy" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.tfstate_block]
}

# PERMISOS DE VFX-ADMIN: control total sobre el bucket

data "aws_iam_policy_document" "vfx_admin_policy" {
  statement {
    sid     = "ControlTotalBucketEstado"
    effect  = "Allow"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]
  }
}

resource "aws_iam_user_policy" "vfx_admin_policy" {
  name   = "vfx-admin-estado-policy"
  user   = aws_iam_user.vfx_admin.name
  policy = data.aws_iam_policy_document.vfx_admin_policy.json
}

# PERMISOS DE LOS GRUPOS DEL ESTUDIO: solo lectura del estado

data "aws_iam_group" "lectores" {
  for_each   = toset(local.grupos_lectores)
  group_name = each.value
}

data "aws_iam_policy_document" "lectura_estado" {
  statement {
    sid       = "ListarBucketEstado"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid       = "LeerObjetosEstado"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_policy" "lectura_estado" {
  name   = "vfx-lectura-estado-policy"
  policy = data.aws_iam_policy_document.lectura_estado.json
}

resource "aws_iam_group_policy_attachment" "lectura_estado_attach" {
  for_each   = data.aws_iam_group.lectores
  group      = each.value.group_name
  policy_arn = aws_iam_policy.lectura_estado.arn
}