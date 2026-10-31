provider "aws" {
  region = "us-east-2"
}

# Busca la VPC que ya creaste en 01-Network
data "aws_vpc" "vfx_vpc" {
  tags = {
    Name = "vfx-vpc"
  }
}

# Subred propia de Revision con Cliente (zona unica, no se replica)
resource "aws_subnet" "revision_cliente_subnet" {
  vpc_id     = data.aws_vpc.vfx_vpc.id
  cidr_block = "10.0.8.0/24"

  tags = {
    Name         = "revision-cliente-subnet"
    departamento = "revision-cliente"
    proyecto     = "pipeline-vfx"
  }
}
# Bucket de entregas al cliente (origen de CloudFront)
resource "aws_s3_bucket" "cliente_entregas" {
  bucket = "vfx-cliente-entregas"

  tags = {
    Name         = "vfx-cliente-entregas"
    departamento = "revision-cliente"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_s3_bucket_public_access_block" "cliente_entregas" {
  bucket = aws_s3_bucket.cliente_entregas.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Identidad de acceso de origen: asi CloudFront puede leer del bucket
# sin que el bucket quede abierto a internet
resource "aws_cloudfront_origin_access_identity" "cliente_oai" {
  comment = "OAI para entregas a cliente - vfx-cliente-entregas"
}

data "aws_iam_policy_document" "cliente_entregas_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.cliente_entregas.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.cliente_oai.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.cliente_entregas.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.cliente_oai.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cliente_entregas" {
  bucket = aws_s3_bucket.cliente_entregas.id
  policy = data.aws_iam_policy_document.cliente_entregas_policy.json
}

# Llave publica (generada con OpenSSL) y grupo de llaves de confianza
# para poder exigir URLs firmadas
resource "aws_cloudfront_public_key" "cliente_signer" {
  name        = "vfx-cliente-signer-key"
  comment     = "Llave publica para firmar URLs de Revision con Cliente"
  encoded_key = file("cloudfront_public_key.pem")
}

resource "aws_cloudfront_key_group" "cliente_key_group" {
  name    = "vfx-cliente-key-group"
  comment = "Grupo de llaves de confianza para URLs firmadas de cliente"
  items   = [aws_cloudfront_public_key.cliente_signer.id]
}

# Distribucion de CloudFront
resource "aws_cloudfront_distribution" "cliente_dist" {
  enabled = true
  comment = "Distribucion de Revision con Cliente - vfx-cliente-entregas"

  origin {
    domain_name = aws_s3_bucket.cliente_entregas.bucket_regional_domain_name
    origin_id   = "vfx-cliente-entregas-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.cliente_oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "vfx-cliente-entregas-origin"

    viewer_protocol_policy = "redirect-to-https"
    trusted_key_groups     = [aws_cloudfront_key_group.cliente_key_group.id]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name         = "vfx-cliente-dist"
    departamento = "revision-cliente"
    proyecto     = "pipeline-vfx"
  }
}