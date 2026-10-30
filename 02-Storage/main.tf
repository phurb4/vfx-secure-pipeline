provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "modelado_input" {
  bucket = "vfx-modelado-input"

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_s3_bucket_versioning" "modelado_input_versioning" {
  bucket = aws_s3_bucket.modelado_input.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "modelado_output" {
  bucket = "vfx-modelado-output"

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_s3_bucket_versioning" "modelado_output_versioning" {
  bucket = aws_s3_bucket.modelado_output.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "dailies" {
  bucket = "vfx-dailies"

  tags = {
    ambito   = "compartido"
    proyecto = "pipeline-vfx"
  }
}

resource "aws_s3_bucket_versioning" "dailies_versioning" {
  bucket = aws_s3_bucket.dailies.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "modelado_metadata" {
  name         = "vfx-modelado-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "asset_id"
  range_key    = "version"

  attribute {
    name = "asset_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "modelado_input_encryption" {
  bucket = aws_s3_bucket.modelado_input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "modelado_input_block" {
  bucket                  = aws_s3_bucket.modelado_input.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "modelado_output_encryption" {
  bucket = aws_s3_bucket.modelado_output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "modelado_output_block" {
  bucket                  = aws_s3_bucket.modelado_output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dailies_encryption" {
  bucket = aws_s3_bucket.dailies.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dailies_block" {
  bucket                  = aws_s3_bucket.dailies.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
module "texturing_storage" {
  source       = "../modules/storage-base"
  departamento = "texturing"
}

module "rigging_storage" {
  source       = "../modules/storage-base"
  departamento = "rigging"
}

module "animation_storage" {
  source       = "../modules/storage-base"
  departamento = "animation"
}

module "fx_storage" {
  source       = "../modules/storage-base"
  departamento = "fx"
}

module "compositing_storage" {
  source       = "../modules/storage-base"
  departamento = "compositing"
}
resource "aws_dynamodb_table" "texturing_metadata" {
  name         = "vfx-texturing-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "asset_id"
  range_key    = "version"

  attribute {
    name = "asset_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    departamento = "texturing"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_dynamodb_table" "rigging_metadata" {
  name         = "vfx-rigging-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "asset_id"
  range_key    = "version"

  attribute {
    name = "asset_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    departamento = "rigging"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_dynamodb_table" "animation_metadata" {
  name         = "vfx-animation-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "asset_id"
  range_key    = "version"

  attribute {
    name = "asset_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    departamento = "animation"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_dynamodb_table" "fx_metadata" {
  name         = "vfx-fx-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "asset_id"
  range_key    = "version"

  attribute {
    name = "asset_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    departamento = "fx"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_dynamodb_table" "compositing_metadata" {
  name         = "vfx-compositing-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "asset_id"
  range_key    = "version"

  attribute {
    name = "asset_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    departamento = "compositing"
    proyecto     = "pipeline-vfx"
  }
}