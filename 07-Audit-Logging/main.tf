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
    s3             = "http://localhost:4566"
    iam            = "http://localhost:4566"
    sns            = "http://localhost:4566"
    cloudtrail     = "http://localhost:4566"
    cloudwatchlogs = "http://localhost:4566"
  }
}

variable "account_id" {
  description = "ID de la cuenta (ficticia en Floci). Se usa para armar ARNs a mano, porque el provider no consulta la cuenta."
  type        = string
}

variable "alert_email" {
  description = "Mail que recibe las alertas de seguridad."
  type        = string
}

locals {
  trail_name = "vfx-audit-trail"
  trail_arn  = "arn:aws:cloudtrail:us-east-1:${var.account_id}:trail/vfx-audit-trail"

  common_tags = {
    proyecto     = "pipeline-vfx"
    departamento = "seguridad"
    ambiente     = "desarrollo"
  }
}

# --- Bucket donde CloudTrail guarda los registros ---

resource "aws_s3_bucket" "audit_logs" {
  bucket = "vfx-audit-logs"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Los registros de auditoria nunca deben ser publicos
resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket                  = aws_s3_bucket.audit_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Politica que AWS exige para que CloudTrail pueda escribir en el bucket
resource "aws_s3_bucket_policy" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.audit_logs.arn
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.audit_logs.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      }
    ]
  })
}

# --- CloudWatch Logs: segundo destino de los eventos (base de las alarmas) ---

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/vfx/cloudtrail"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_iam_role" "cloudtrail_to_logs" {
  name = "vfx-cloudtrail-to-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "cloudtrail_to_logs" {
  name = "vfx-cloudtrail-to-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_to_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# --- SNS: alertas de seguridad ---

resource "aws_sns_topic" "security_alerts" {
  name = "vfx-security-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- CloudTrail: el trail con sus event selectors ---

resource "aws_cloudtrail" "audit" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.audit_logs.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_logs.arn

  # Eventos de gestion (crear usuario, cambiar politicas, etc.) + eventos de datos
  # del bucket de Output de Modelado. Los buckets de Output de Render Final y de
  # Revision con Cliente se suman cuando existan.
  
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = [
        "arn:aws:s3:::vfx-modelado-output/",
        "arn:aws:s3:::vfx-texturing-output/",
        "arn:aws:s3:::vfx-animation-output/",
        "arn:aws:s3:::vfx-rigging-output/",
        "arn:aws:s3:::vfx-fx-output/",
        "arn:aws:s3:::vfx-compositing-output/",
        "arn:aws:s3:::vfx-cliente-entregas/",
        "arn:aws:s3:::vfx-render-final-output/",
      ]
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_s3_bucket_policy.audit_logs,
    aws_iam_role_policy.cloudtrail_to_logs,
  ]
}
variable "enable_security_alarms" {
  description = "Interruptor de la segunda tanda (metric filters + alarmas). Apagado en Floci (no soporta DescribeMetricFilters), encendido en AWS real."
  type        = bool
  default     = false
}
# --- Alarma 1: accesos denegados (IP fuera de la VPN + Artista/Lead fuera de horario) ---
# Ambos casos los genera la politica de IAM como un evento con errorCode de tipo
# "AccessDenied" o "*UnauthorizedOperation". Es una sola senal honesta, no dos.

resource "aws_cloudwatch_log_metric_filter" "accesos_denegados" {
  count = var.enable_security_alarms ? 1 : 0

  name           = "vfx-accesos-denegados"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"

  metric_transformation {
    name          = "AccesosDenegados"
    namespace     = "VFX/Seguridad"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "accesos_denegados" {
  count = var.enable_security_alarms ? 1 : 0

  alarm_name          = "vfx-accesos-denegados"
  alarm_description   = "Se denego uno o mas accesos: IP fuera de la VPN o Artista/Lead fuera de horario."
  namespace           = "VFX/Seguridad"
  metric_name         = "AccesosDenegados"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]

  tags = local.common_tags
}
# --- Alarma 2: descargas masivas (insider legitimo exfiltrando) ---
# Cuenta eventos GetObject de S3 capturados por el trail. No mide bytes (un metric
# filter no puede sumar volumen), mide CANTIDAD: muchas descargas en poco tiempo es
# la huella de alguien bajandose un proyecto entero. El volumen real por bytes queda
# documentado para una pieza posterior (GuardDuty / metricas de S3), ver bloque 09.

resource "aws_cloudwatch_log_metric_filter" "descargas_masivas" {
  count = var.enable_security_alarms ? 1 : 0

  name           = "vfx-descargas-masivas"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = "{ ($.eventSource = \"s3.amazonaws.com\") && ($.eventName = \"GetObject\") }"

  metric_transformation {
    name          = "DescargasS3"
    namespace     = "VFX/Seguridad"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "descargas_masivas" {
  count = var.enable_security_alarms ? 1 : 0

  alarm_name          = "vfx-descargas-masivas"
  alarm_description   = "Volumen inusual de descargas (GetObject) en una ventana corta: posible exfiltracion por un usuario legitimo."
  namespace           = "VFX/Seguridad"
  metric_name         = "DescargasS3"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 100
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]

  tags = local.common_tags
}

# --- Alarma 3: supervisor con acceso fuera de horario ---
# Un metric filter no sabe que hora es. Esta Lambda recibe los eventos del log group,
# mira el eventTime (siempre en UTC) y, si cae fuera del rango laboral, publica a SNS.
# Cubre el caso que las alarmas de texto no pueden: el acceso EXITOSO del supervisor
# fuera de horario (los bloqueos de Artista/Lead ya los agarra la alarma 1).

data "archive_file" "horario_lambda" {
  count = var.enable_security_alarms ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/horario_lambda.zip"

  source {
    filename = "index.py"
    content  = <<-PYTHON
      import base64
      import gzip
      import json
      import os
      import boto3

      sns = boto3.client("sns")

      TOPIC_ARN = os.environ["TOPIC_ARN"]
      HORA_INICIO = int(os.environ.get("HORA_INICIO", "9"))
      HORA_FIN = int(os.environ.get("HORA_FIN", "18"))

      def handler(event, context):
          comprimido = base64.b64decode(event["awslogs"]["data"])
          payload = json.loads(gzip.decompress(comprimido))

          if payload.get("messageType") == "CONTROL_MESSAGE":
              return

          for registro in payload["logEvents"]:
              try:
                  evento = json.loads(registro["message"])
              except json.JSONDecodeError:
                  continue

              event_time = evento.get("eventTime", "")
              # Formato: 2026-10-12T20:30:00Z -> la hora UTC son los caracteres 11 y 12
              try:
                  hora = int(event_time[11:13])
              except (ValueError, IndexError):
                  continue

              if hora < HORA_INICIO or hora >= HORA_FIN:
                  usuario = evento.get("userIdentity", {}).get("arn", "desconocido")
                  sns.publish(
                      TopicArn=TOPIC_ARN,
                      Subject="VFX: acceso fuera de horario",
                      Message=(
                          f"Acceso fuera de horario laboral.\n"
                          f"Usuario: {usuario}\n"
                          f"Hora UTC del evento: {event_time}\n"
                          f"Accion: {evento.get('eventName', 'desconocida')}"
                      ),
                  )
          return {"statusCode": 200}
    PYTHON
  }
}
resource "aws_iam_role" "horario_lambda" {
  count = var.enable_security_alarms ? 1 : 0

  name = "vfx-horario-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "horario_lambda" {
  count = var.enable_security_alarms ? 1 : 0

  name = "vfx-horario-lambda-policy"
  role = aws_iam_role.horario_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"]
        Resource = "arn:aws:logs:us-east-1:${var.account_id}:log-group:/aws/lambda/vfx-horario-alarma:*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}
resource "aws_lambda_function" "horario_alarma" {
  count = var.enable_security_alarms ? 1 : 0

  function_name    = "vfx-horario-alarma"
  role             = aws_iam_role.horario_lambda[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.horario_lambda[0].output_path
  source_code_hash = data.archive_file.horario_lambda[0].output_base64sha256

  environment {
    variables = {
      TOPIC_ARN   = aws_sns_topic.security_alerts.arn
      HORA_INICIO = "12"
      HORA_FIN    = "21"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "horario_desde_logs" {
  count = var.enable_security_alarms ? 1 : 0

  statement_id  = "AllowCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.horario_alarma[0].function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "horario" {
  count = var.enable_security_alarms ? 1 : 0

  name            = "vfx-horario-filter"
  log_group_name  = aws_cloudwatch_log_group.cloudtrail.name
  filter_pattern  = "{ $.errorCode NOT EXISTS }"
  destination_arn = aws_lambda_function.horario_alarma[0].arn

  depends_on = [aws_lambda_permission.horario_desde_logs]
}
# --- Alarma 4: falla de la Lambda vfx-horario ---
# Si vfx-horario falla a la hora de cierre, el acceso de Artista y Lead queda abierto
# hasta el dia siguiente. Usa la metrica Errors que Lambda publica sola (no depende de
# CloudTrail). Un solo error en 5 minutos ya dispara el aviso.

resource "aws_cloudwatch_metric_alarm" "horario_lambda_errores" {
  count = var.enable_security_alarms ? 1 : 0

  alarm_name          = "vfx-horario-lambda-errores"
  alarm_description   = "La Lambda vfx-horario fallo: el cierre o la apertura de acceso por horario puede no haberse aplicado."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = "vfx-horario" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]

  tags = local.common_tags
}
# --- Alarma 5: falla de las Lambdas de dailies (una alarma por funcion) ---
# Las Lambdas de dailies son invocadas por S3 de forma asincrona: si fallan, Lambda
# reintenta y descarta, sin ningun aviso. Usa la metrica Errors que Lambda publica sola.

locals {
  lambdas_dailies = toset([
    "vfx-modelado-imagen-dailies",
    "vfx-texturing-imagen-dailies",
    "vfx-rigging-imagen-dailies",
    "vfx-animation-video-burn",
    "vfx-fx-video-burn",
    "vfx-compositing-video-burn",
    "vfx-render-final-video-burn",
  ])
}

resource "aws_cloudwatch_metric_alarm" "dailies_lambda_errores" {
  for_each = var.enable_security_alarms ? local.lambdas_dailies : toset([])

  alarm_name          = "${each.key}-errores"
  alarm_description   = "La Lambda ${each.key} fallo: un archivo subido puede no haber llegado a dailies."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.key }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]

  tags = local.common_tags
}