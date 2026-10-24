# RENDER FINAL: almacenamiento propio, igual que el resto de los departamentos.
# Buckets vfx-render-final-input y vfx-render-final-output (los crea el modulo).
module "render_final_storage" {
  source       = "../modules/storage-base"
  departamento = "render-final"
}

# Tabla de metadata del departamento (el modulo no la crea, igual que en los demas).
resource "aws_dynamodb_table" "render_final_metadata" {
  name         = "vfx-render-final-metadata"
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
    departamento = "render-final"
    proyecto     = "pipeline-vfx"
  }
}