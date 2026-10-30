provider "aws" {
  region = "us-east-2"
}

resource "aws_vpc" "vfx_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name     = "vfx-vpc"
    proyecto = "pipeline-vfx"
  }
}

resource "aws_subnet" "modelado_subnet" {
  vpc_id     = aws_vpc.vfx_vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name         = "modelado-subnet"
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

# NACL de Modelado: ahora sin reglas inline, se define vacia y las reglas
# se agregan por separado abajo con aws_network_acl_rule (mas granular).
resource "aws_network_acl" "modelado_nacl" {
  vpc_id     = aws_vpc.vfx_vpc.id
  subnet_ids = [aws_subnet.modelado_subnet.id]

  tags = {
    Name         = "modelado-nacl"
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

# Entrada: permite HTTPS (443) solo desde el rango interno de la VPC
resource "aws_network_acl_rule" "modelado_in_https" {
  network_acl_id = aws_network_acl.modelado_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.1.0/24"
  from_port      = 443
  to_port        = 443
}

# Entrada: permite puertos efimeros (respuestas a conexiones salientes)
resource "aws_network_acl_rule" "modelado_in_ephemeral" {
  network_acl_id = aws_network_acl.modelado_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.1.0/24"
  from_port      = 1024
  to_port        = 65535
}

# Salida: permite HTTPS (443) hacia el rango interno de la VPC
resource "aws_network_acl_rule" "modelado_out_https" {
  network_acl_id = aws_network_acl.modelado_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.1.0/24"
  from_port      = 443
  to_port        = 443
}

# Salida: permite puertos efimeros (para que las respuestas puedan volver)
resource "aws_network_acl_rule" "modelado_out_ephemeral" {
  network_acl_id = aws_network_acl.modelado_nacl.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.1.0/24"
  from_port      = 1024
  to_port        = 65535
}

#####################################

resource "aws_security_group" "modelado_estacion_sg" {
  name        = "modelado-estacion-remota-sg"
  description = "Security group para la estacion de trabajo remota de Modelado (Houdini/Solaris)"
  vpc_id      = aws_vpc.vfx_vpc.id

  ingress {
    description = "Escritorio remoto solo desde la red interna de la VPN"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description     = "Salida HTTPS hacia S3 via VPC Endpoint"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    prefix_list_ids  = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  }

  tags = {
    Name         = "modelado-estacion-remota-sg"
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_security_group" "render_farm_sg" {
  name        = "render-farm-sg"
  description = "Render farm: sin trafico entrante, salida solo HTTPS"
  vpc_id      = aws_vpc.vfx_vpc.id

  egress {
    description     = "HTTPS hacia el VPC Endpoint de S3"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  }

  egress {
    description = "HTTPS hacia el VPC Endpoint de SQS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.7.0/24"]
  }

  tags = {
    Name         = "render-farm-sg"
    proyecto     = "pipeline-vfx"
    departamento = "render-final"
  }
}
resource "aws_subnet" "texturing_subnet" {
  vpc_id     = aws_vpc.vfx_vpc.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name         = "texturing-subnet"
    departamento = "texturing"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl" "texturing_nacl" {
  vpc_id     = aws_vpc.vfx_vpc.id
  subnet_ids = [aws_subnet.texturing_subnet.id]

  tags = {
    Name         = "texturing-nacl"
    departamento = "texturing"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl_rule" "texturing_in_https" {
  network_acl_id = aws_network_acl.texturing_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.2.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "texturing_in_ephemeral" {
  network_acl_id = aws_network_acl.texturing_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.2.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "texturing_out_https" {
  network_acl_id = aws_network_acl.texturing_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.2.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "texturing_out_ephemeral" {
  network_acl_id = aws_network_acl.texturing_nacl.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.2.0/24"
  from_port      = 1024
  to_port        = 65535
}
resource "aws_subnet" "rigging_subnet" {
  vpc_id     = aws_vpc.vfx_vpc.id
  cidr_block = "10.0.3.0/24"

  tags = {
    Name         = "rigging-subnet"
    departamento = "rigging"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl" "rigging_nacl" {
  vpc_id     = aws_vpc.vfx_vpc.id
  subnet_ids = [aws_subnet.rigging_subnet.id]

  tags = {
    Name         = "rigging-nacl"
    departamento = "rigging"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl_rule" "rigging_in_https" {
  network_acl_id = aws_network_acl.rigging_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.3.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "rigging_in_ephemeral" {
  network_acl_id = aws_network_acl.rigging_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.3.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "rigging_out_https" {
  network_acl_id = aws_network_acl.rigging_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.3.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "rigging_out_ephemeral" {
  network_acl_id = aws_network_acl.rigging_nacl.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.3.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_subnet" "animation_subnet" {
  vpc_id     = aws_vpc.vfx_vpc.id
  cidr_block = "10.0.4.0/24"

  tags = {
    Name         = "animation-subnet"
    departamento = "animation"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl" "animation_nacl" {
  vpc_id     = aws_vpc.vfx_vpc.id
  subnet_ids = [aws_subnet.animation_subnet.id]

  tags = {
    Name         = "animation-nacl"
    departamento = "animation"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl_rule" "animation_in_https" {
  network_acl_id = aws_network_acl.animation_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.4.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "animation_in_ephemeral" {
  network_acl_id = aws_network_acl.animation_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.4.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "animation_out_https" {
  network_acl_id = aws_network_acl.animation_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.4.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "animation_out_ephemeral" {
  network_acl_id = aws_network_acl.animation_nacl.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.4.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_subnet" "fx_subnet" {
  vpc_id     = aws_vpc.vfx_vpc.id
  cidr_block = "10.0.5.0/24"

  tags = {
    Name         = "fx-subnet"
    departamento = "fx"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl" "fx_nacl" {
  vpc_id     = aws_vpc.vfx_vpc.id
  subnet_ids = [aws_subnet.fx_subnet.id]

  tags = {
    Name         = "fx-nacl"
    departamento = "fx"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl_rule" "fx_in_https" {
  network_acl_id = aws_network_acl.fx_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.5.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "fx_in_ephemeral" {
  network_acl_id = aws_network_acl.fx_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.5.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "fx_out_https" {
  network_acl_id = aws_network_acl.fx_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.5.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "fx_out_ephemeral" {
  network_acl_id = aws_network_acl.fx_nacl.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.5.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_subnet" "compositing_subnet" {
  vpc_id     = aws_vpc.vfx_vpc.id
  cidr_block = "10.0.6.0/24"

  tags = {
    Name         = "compositing-subnet"
    departamento = "compositing"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl" "compositing_nacl" {
  vpc_id     = aws_vpc.vfx_vpc.id
  subnet_ids = [aws_subnet.compositing_subnet.id]

  tags = {
    Name         = "compositing-nacl"
    departamento = "compositing"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_network_acl_rule" "compositing_in_https" {
  network_acl_id = aws_network_acl.compositing_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.6.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "compositing_in_ephemeral" {
  network_acl_id = aws_network_acl.compositing_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.6.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "compositing_out_https" {
  network_acl_id = aws_network_acl.compositing_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.6.0/24"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "compositing_out_ephemeral" {
  network_acl_id = aws_network_acl.compositing_nacl.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "10.0.6.0/24"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id          = aws_vpc.vfx_vpc.id
  service_name    = "com.amazonaws.us-east-2.s3"
  route_table_ids = [aws_vpc.vfx_vpc.main_route_table_id]

  tags = {
    Name     = "vfx-s3-endpoint"
    proyecto = "pipeline-vfx"
  }
}

resource "aws_vpc_endpoint" "sqs_endpoint" {
  vpc_id              = aws_vpc.vfx_vpc.id
  service_name        = "com.amazonaws.us-east-2.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.modelado_subnet.id]
  security_group_ids  = [aws_security_group.sqs_endpoint_sg.id]

  tags = {
    Name     = "vfx-sqs-endpoint"
    proyecto = "pipeline-vfx"
  }
}

resource "aws_security_group" "sqs_endpoint_sg" {
  name        = "vfx-sqs-endpoint-sg"
  description = "Security group para el VPC Endpoint de SQS, acepta HTTPS desde la subred de Modelado"
  vpc_id      = aws_vpc.vfx_vpc.id

  ingress {
    description = "HTTPS desde la subred de Modelado hacia el endpoint de SQS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }
  ingress {
    description = "HTTPS desde la subred de Render Final hacia el endpoint de SQS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.7.0/24"]
  }

  tags = {
    Name     = "vfx-sqs-endpoint-sg"
    proyecto = "pipeline-vfx"
  }
}
resource "aws_security_group" "texturing_estacion_sg" {
  name        = "texturing-estacion-remota-sg"
  description = "Security group para la estacion de trabajo remota de Texturing"
  vpc_id      = aws_vpc.vfx_vpc.id

  ingress {
    description = "Escritorio remoto solo desde la red interna de la VPN"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description     = "Salida HTTPS hacia S3 via VPC Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  }

  tags = {
    Name         = "texturing-estacion-remota-sg"
    departamento = "texturing"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_security_group" "rigging_estacion_sg" {
  name        = "rigging-estacion-remota-sg"
  description = "Security group para la estacion de trabajo remota de Rigging"
  vpc_id      = aws_vpc.vfx_vpc.id

  ingress {
    description = "Escritorio remoto solo desde la red interna de la VPN"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description     = "Salida HTTPS hacia S3 via VPC Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  }

  tags = {
    Name         = "rigging-estacion-remota-sg"
    departamento = "rigging"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_security_group" "animation_estacion_sg" {
  name        = "animation-estacion-remota-sg"
  description = "Security group para la estacion de trabajo remota de Animation"
  vpc_id      = aws_vpc.vfx_vpc.id

  ingress {
    description = "Escritorio remoto solo desde la red interna de la VPN"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description     = "Salida HTTPS hacia S3 via VPC Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  }

  tags = {
    Name         = "animation-estacion-remota-sg"
    departamento = "animation"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_security_group" "fx_estacion_sg" {
  name        = "fx-estacion-remota-sg"
  description = "Security group para la estacion de trabajo remota de FX"
  vpc_id      = aws_vpc.vfx_vpc.id

  ingress {
    description = "Escritorio remoto solo desde la red interna de la VPN"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description     = "Salida HTTPS hacia S3 via VPC Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  }

  tags = {
    Name         = "fx-estacion-remota-sg"
    departamento = "fx"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_security_group" "compositing_estacion_sg" {
  name        = "compositing-estacion-remota-sg"
  description = "Security group para la estacion de trabajo remota de Compositing"
  vpc_id      = aws_vpc.vfx_vpc.id

  ingress {
    description = "Escritorio remoto solo desde la red interna de la VPN"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description     = "Salida HTTPS hacia S3 via VPC Endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  }

  tags = {
    Name         = "compositing-estacion-remota-sg"
    departamento = "compositing"
    proyecto     = "pipeline-vfx"
  }
}