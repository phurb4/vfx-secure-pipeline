

variable "aws_access_key" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}

variable "alert_email" {
  type      = string
  sensitive = true
}
variable "sns_endpoint" {
  description = "Endpoint de SNS que usa la Lambda de aviso a invitados. En Floci: dejar vacio para que la Lambda use la red interna de Floci. En AWS real: vacio tambien."
  type        = string
  default     = ""
}
provider "aws" {
  region                      = "us-east-1"
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    cognitoidp = "http://localhost:4566"
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    events     = "http://localhost:4566"
    sns        = "http://localhost:4566"
    ec2        = "http://localhost:4566"
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket                      = "vfx-tfstate"
    key                         = "01-network/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "http://localhost:4566" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
  }
}

resource "aws_cognito_user_pool" "equipo_interno" {
  name = "vfx-equipo-interno"

  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  username_attributes     = ["email"]
  auto_verified_attributes = ["email"]

  tags = {
    proyecto = "pipeline-vfx"
  }
}

resource "aws_cognito_user_pool_client" "equipo_interno_client" {
  name         = "vfx-equipo-interno-client"
  user_pool_id = aws_cognito_user_pool.equipo_interno.id
}

resource "aws_cognito_user_pool" "clientes" {
  name = "vfx-clientes"

  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

    lambda_config {
    pre_sign_up = aws_lambda_function.pre_signup_domain.arn
  }

  tags = {
    proyecto = "pipeline-vfx"
  }
}

resource "aws_cognito_user_pool_client" "clientes_client" {
  name         = "vfx-clientes-client"
  user_pool_id = aws_cognito_user_pool.clientes.id
}

resource "aws_cognito_user_pool" "invitados" {
  name = "vfx-invitados"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  lambda_config {
    post_authentication = aws_lambda_function.guest_login_notify.arn
  }
  tags = {
    proyecto = "pipeline-vfx"
  }
}

resource "aws_cognito_user_pool_client" "invitados_client" {
  name         = "vfx-invitados-client"
  user_pool_id = aws_cognito_user_pool.invitados.id

  explicit_auth_flows = ["ALLOW_USER_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "hours"
  }
}

# ===================================================================
# ABAC (Attribute-Based Access Control) - departamentos del pipeline
# ===================================================================
# Una unica condicion basada en la etiqueta "departamento" del usuario
# (aws:PrincipalTag/departamento), comparada contra la etiqueta de cada
# bucket S3 y tabla DynamoDB (bloque 02-Storage). Los 7 departamentos
# siguen el patron vfx-<departamento>-input, vfx-<departamento>-output,
# vfx-dailies/<departamento>/ y vfx-<departamento>-metadata.
#
# HORARIO (sesion del 23 de octubre de 2026): las politicas de trabajo
# (los Allow de ABAC) viven en horario.tf y las adjunta/saca la Lambda
# "vfx-horario". Aca solo queda la politica fija de cada grupo (bloqueo
# de IP). Ver horario.tf para el detalle completo del diseno.
# ===================================================================

# ARTISTA
resource "aws_iam_group" "artista" {
  name = "vfx-artista"
}

data "aws_iam_policy_document" "artista_policy" {
  statement {
    sid       = "DenyFueraDeIP"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:SourceIp"
      values   = local.ips_permitidas
    }

    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:VpcSourceIp"
      values   = local.ips_permitidas
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "aws:SourceVpc"
      values   = [data.terraform_remote_state.network.outputs.vpc_id]
    }
  }
}

resource "aws_iam_policy" "artista_policy" {
  name   = "vfx-artista-policy"
  policy = data.aws_iam_policy_document.artista_policy.json
}

resource "aws_iam_group_policy_attachment" "artista_attach" {
  group      = aws_iam_group.artista.name
  policy_arn = aws_iam_policy.artista_policy.arn
}

# LEAD
resource "aws_iam_group" "lead" {
  name = "vfx-lead"
}

data "aws_iam_policy_document" "lead_policy" {
  statement {
    sid       = "DenyFueraDeIP"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:SourceIp"
      values   = local.ips_permitidas
    }

    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:VpcSourceIp"
      values   = local.ips_permitidas
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "aws:SourceVpc"
      values   = [data.terraform_remote_state.network.outputs.vpc_id]
    }
  }
}

resource "aws_iam_policy" "lead_policy" {
  name   = "vfx-lead-policy"
  policy = data.aws_iam_policy_document.lead_policy.json
}

resource "aws_iam_group_policy_attachment" "lead_attach" {
  group      = aws_iam_group.lead.name
  policy_arn = aws_iam_policy.lead_policy.arn
}

# SUPERVISOR DE DEPARTAMENTO
resource "aws_iam_group" "supervisor_departamento" {
  name = "vfx-supervisor-departamento"
}

data "aws_iam_policy_document" "supervisor_departamento_policy" {
  statement {
    sid       = "DenyFueraDeIP"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:SourceIp"
      values   = local.ips_permitidas
    }

    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:VpcSourceIp"
      values   = local.ips_permitidas
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "aws:SourceVpc"
      values   = [data.terraform_remote_state.network.outputs.vpc_id]
    }
  }

  statement {
    sid    = "ABACAccesoSoloASuDepartamentoS3"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::vfx-$${aws:PrincipalTag/departamento}-input",
      "arn:aws:s3:::vfx-$${aws:PrincipalTag/departamento}-input/*",
      "arn:aws:s3:::vfx-$${aws:PrincipalTag/departamento}-output",
      "arn:aws:s3:::vfx-$${aws:PrincipalTag/departamento}-output/*",
    ]
  }

  statement {
    sid       = "ABACDailiesListarSoloSuCarpeta"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::vfx-dailies"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["$${aws:PrincipalTag/departamento}/*"]
    }
  }

  statement {
    sid    = "ABACDailiesObjetosSoloSuCarpeta"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::vfx-dailies/$${aws:PrincipalTag/departamento}/*"]
  }

  statement {
    sid    = "ABACAccesoSoloASuDepartamentoDynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
    ]
    resources = [
      "arn:aws:dynamodb:*:*:table/vfx-$${aws:PrincipalTag/departamento}-metadata",
    ]
  }
}

resource "aws_iam_policy" "supervisor_departamento_policy" {
  name   = "vfx-supervisor-departamento-policy"
  policy = data.aws_iam_policy_document.supervisor_departamento_policy.json
}

resource "aws_iam_group_policy_attachment" "supervisor_departamento_attach" {
  group      = aws_iam_group.supervisor_departamento.name
  policy_arn = aws_iam_policy.supervisor_departamento_policy.arn
}

# SUPERVISOR VFX GENERAL
resource "aws_iam_group" "supervisor_vfx_general" {
  name = "vfx-supervisor-vfx-general"
}

data "aws_iam_policy_document" "supervisor_vfx_general_policy" {
  # PROVISORIO: la definicion final de "IP habitual" queda atada a la decision de IP
  # pendiente (aws:SourceIp vs aws:SourceVpc, camino de acceso por internet).
  statement {
    sid       = "ExigirMFASiIPDistinta"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:SourceIp"
      values   = local.ips_permitidas
    }

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }

  statement {
    sid     = "TodosLosDepartamentosS3"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
    resources = flatten([
      for d in local.horario_departamentos : [
        "arn:aws:s3:::vfx-${d}-input",
        "arn:aws:s3:::vfx-${d}-input/*",
        "arn:aws:s3:::vfx-${d}-output",
        "arn:aws:s3:::vfx-${d}-output/*",
      ]
    ])
  }

  statement {
    sid     = "TodasLasCarpetasDeDailies"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::vfx-dailies",
      "arn:aws:s3:::vfx-dailies/*",
    ]
  }

  statement {
    sid     = "TodasLasTablasDeMetadata"
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
    resources = [
      for d in local.horario_departamentos : "arn:aws:dynamodb:*:*:table/vfx-${d}-metadata"
    ]
  }
}

resource "aws_iam_policy" "supervisor_vfx_general_policy" {
  name   = "vfx-supervisor-vfx-general-policy"
  policy = data.aws_iam_policy_document.supervisor_vfx_general_policy.json
}

resource "aws_iam_group_policy_attachment" "supervisor_vfx_general_attach" {
  group      = aws_iam_group.supervisor_vfx_general.name
  policy_arn = aws_iam_policy.supervisor_vfx_general_policy.arn
}

# GUEST-VIEWER: grupo de IAM de solo lectura
resource "aws_iam_group" "guest_viewer" {
  name = "vfx-guest-viewer"
}

data "aws_iam_policy_document" "guest_viewer_policy" {
  statement {
    sid       = "LecturaListadoBucketEntregas"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::vfx-cliente-entregas"]
  }

  statement {
    sid       = "LecturaObjetosBucketEntregas"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::vfx-cliente-entregas/*"]
  }
}

resource "aws_iam_policy" "guest_viewer_policy" {
  name   = "vfx-guest-viewer-policy"
  policy = data.aws_iam_policy_document.guest_viewer_policy.json
}

resource "aws_iam_group_policy_attachment" "guest_viewer_attach" {
  group      = aws_iam_group.guest_viewer.name
  policy_arn = aws_iam_policy.guest_viewer_policy.arn
}

# SNS: aviso de acceso de invitados
resource "aws_sns_topic" "guest_login" {
  name = "vfx-guest-login-alerts"

  tags = {
    proyecto = "pipeline-vfx"
  }
}

resource "aws_sns_topic_subscription" "guest_login_email" {
  topic_arn = aws_sns_topic.guest_login.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# LAMBDA: se ejecuta despues de cada login exitoso de un invitado
resource "aws_iam_role" "lambda_guest_notify_role" {
  name = "vfx-lambda-guest-notify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

data "aws_iam_policy_document" "lambda_guest_notify_policy" {
  statement {
    sid       = "PublicarSoloEnTopicoDeInvitados"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.guest_login.arn]
  }
}

resource "aws_iam_role_policy" "lambda_guest_notify_policy" {
  name   = "vfx-lambda-guest-notify-policy"
  role   = aws_iam_role.lambda_guest_notify_role.id
  policy = data.aws_iam_policy_document.lambda_guest_notify_policy.json
}

data "archive_file" "lambda_guest_notify_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_guest_notify.zip"

  source {
    content  = <<EOF
import os
import boto3
from datetime import datetime, timezone

def handler(event, context):
    sns = boto3.client("sns", endpoint_url=os.environ.get("SNS_ENDPOINT") or None, region_name="us-east-1")
    email = event["request"]["userAttributes"].get("email", "desconocido")
    cuando = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    try:
        sns.publish(
            TopicArn=os.environ["TOPIC_ARN"],
            Subject="Acceso de invitado - VFX Pipeline",
            Message="Entro un invitado. Email: " + email + " - Momento: " + cuando,
        )
    except Exception as e:
        print("No se pudo publicar en SNS: " + str(e))
    return event
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "guest_login_notify" {
  function_name    = "vfx-guest-login-notify"
  role             = aws_iam_role.lambda_guest_notify_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_guest_notify_zip.output_path
  source_code_hash = data.archive_file.lambda_guest_notify_zip.output_base64sha256

  environment {
    variables = {
      TOPIC_ARN = aws_sns_topic.guest_login.arn
      SNS_ENDPOINT = var.sns_endpoint
    }
  }
}

resource "aws_lambda_permission" "allow_cognito_guest_notify" {
  statement_id  = "AllowCognitoInvokeGuestNotify"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guest_login_notify.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.invitados.arn
}

# VALIDACION DE DOMINIO DE EMAIL PARA CLIENTES (pre_sign_up)
resource "aws_iam_role" "lambda_presignup_role" {
  name = "vfx-lambda-presignup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

data "aws_iam_policy_document" "lambda_presignup_logs" {
  statement {
    sid       = "EscribirSoloSusLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/vfx-clientes-presignup:*"]
  }
}

resource "aws_iam_role_policy" "lambda_presignup_logs" {
  name   = "vfx-lambda-presignup-logs"
  role   = aws_iam_role.lambda_presignup_role.id
  policy = data.aws_iam_policy_document.lambda_presignup_logs.json
}

data "archive_file" "lambda_presignup_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_presignup.zip"

  source {
    content  = <<EOF
import os


def handler(event, context):
    allowed = [d.strip().lower() for d in os.environ.get("ALLOWED_DOMAINS", "").split(",") if d.strip()]
    email = event.get("request", {}).get("userAttributes", {}).get("email", "")
    domain = email.rsplit("@", 1)[-1].lower() if "@" in email else ""
    if domain not in allowed:
        raise Exception("Sign-up not allowed for this email domain.")
    return event
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "pre_signup_domain" {
  function_name    = "vfx-clientes-presignup"
  role             = aws_iam_role.lambda_presignup_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_presignup_zip.output_path
  source_code_hash = data.archive_file.lambda_presignup_zip.output_base64sha256

  environment {
    variables = {
      ALLOWED_DOMAINS = "clientdomain.com"
    }
  }
}

resource "aws_lambda_permission" "allow_cognito_presignup" {
  statement_id  = "AllowCognitoInvokePreSignUp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_signup_domain.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.clientes.arn
}

# ===================================================================
# USUARIOS DE PRUEBA PARA VALIDAR ABAC (sesion del 15 de octubre de 2026)
# ===================================================================
# Tres usuarios de IAM de ejemplo, cada uno con el tag "departamento"
# que usa la condicion ABAC de las politicas de arriba, y metidos en
# su grupo correspondiente con aws_iam_user_group_membership (no
# exclusivo: no pisa otras membresias que el usuario pueda tener).
# Sirven unicamente para probar en Floci que el filtro por tag
# realmente deja pasar o bloquea segun corresponda.
# (El usuario de prueba de Render Final esta en horario.tf.)
# ===================================================================

resource "aws_iam_user" "prueba_artista_modelado" {
  name = "prueba-artista-modelado"

  tags = {
    departamento = "modelado"
    rol          = "artista"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_user_group_membership" "prueba_artista_modelado_membership" {
  user = aws_iam_user.prueba_artista_modelado.name
  groups = [
    aws_iam_group.artista.name,
  ]
}

resource "aws_iam_user" "prueba_lead_modelado" {
  name = "prueba-lead-modelado"

  tags = {
    departamento = "modelado"
    rol          = "lead"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_user_group_membership" "prueba_lead_modelado_membership" {
  user = aws_iam_user.prueba_lead_modelado.name
  groups = [
    aws_iam_group.lead.name,
  ]
}

resource "aws_iam_user" "prueba_supervisor_vfx_general" {
  name = "prueba-supervisor-vfx-general"

  tags = {
    rol      = "supervisor-vfx-general"
    proyecto = "pipeline-vfx"
  }
}

resource "aws_iam_user_group_membership" "prueba_supervisor_vfx_general_membership" {
  user = aws_iam_user.prueba_supervisor_vfx_general.name
  groups = [
    aws_iam_group.supervisor_vfx_general.name,
  ]
}

resource "aws_iam_user" "prueba_artista_animacion" {
  name = "prueba-artista-animacion"

  tags = {
    departamento = "animation"
    rol          = "artista"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_user_group_membership" "prueba_artista_animacion_membership" {
  user = aws_iam_user.prueba_artista_animacion.name
  groups = [
    aws_iam_group.artista.name,
  ]
}

resource "aws_iam_user" "prueba_supervisor_modelado" {
  name = "prueba-supervisor-modelado"

  tags = {
    departamento = "modelado"
    rol          = "supervisor-departamento"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_user_group_membership" "prueba_supervisor_modelado_membership" {
  user = aws_iam_user.prueba_supervisor_modelado.name
  groups = [
    aws_iam_group.supervisor_departamento.name,
  ]
}