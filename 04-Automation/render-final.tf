# ============================================================
# Render Final (7mo departamento) - bloque 04-Automation
# Mismo patron que Compositing, con dos diferencias de diseno:
#   1) El mensaje de aprobacion indica que el supervisor manda el
#      trabajo a la cola render-queue a mano (aws sqs send-message).
#   2) Se crea el prefijo render-final/ en el bucket vfx-dailies.
# ============================================================

data "aws_dynamodb_table" "render_final_metadata" {
  name = "vfx-render-final-metadata"
}

# Prefijo render-final/ dentro del bucket compartido vfx-dailies.
# En S3 no existen carpetas: se crea un objeto vacio cuya clave termina en "/".
resource "aws_s3_object" "dailies_render_final_prefix" {
  bucket  = "vfx-dailies"
  key     = "render-final/"
  content = ""
}

resource "aws_sns_topic" "render_final_aprobaciones" {
  name = "vfx-render-final-aprobaciones"
}

resource "aws_sns_topic_subscription" "render_final_supervisor_email" {
  topic_arn = aws_sns_topic.render_final_aprobaciones.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_iam_role" "lambda_render_final_role" {
  name = "vfx-lambda-render-final-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_render_final_policy" {
  name = "vfx-lambda-render-final-policy"
  role = aws_iam_role.lambda_render_final_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = data.aws_dynamodb_table.render_final_metadata.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/vfx-render-final-version-namer:*"
      }
    ]
  })
}

data "archive_file" "render_final_version_namer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/version_namer.py"
  output_path = "${path.module}/render_final_version_namer.zip"
}

resource "aws_lambda_function" "render_final_version_namer" {
  function_name    = "vfx-render-final-version-namer"
  role             = aws_iam_role.lambda_render_final_role.arn
  handler          = "version_namer.lambda_handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.render_final_version_namer_zip.output_path
  source_code_hash = data.archive_file.render_final_version_namer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME      = data.aws_dynamodb_table.render_final_metadata.name
      DEPT_PREFIX     = "RF"
      DEPARTMENT_NAME = "render-final"
    }
  }

  tags = {
    departamento = "render-final"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_role" "sfn_render_final_role" {
  name = "vfx-sfn-render-final-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_render_final_policy" {
  name = "vfx-sfn-render-final-policy"
  role = aws_iam_role.sfn_render_final_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.render_final_version_namer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.render_final_aprobaciones.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = data.aws_dynamodb_table.render_final_metadata.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "render_final_aprobacion" {
  name     = "vfx-render-final-aprobacion"
  role_arn = aws_iam_role.sfn_render_final_role.arn

  definition = jsonencode({
    Comment = "Flujo de aprobacion Render Final"
    StartAt = "AsignarVersion"
    States = {
      AsignarVersion = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.render_final_version_namer.arn
          "Payload.$"  = "$"
        }
        ResultSelector = {
          "asset_id.$"  = "$.Payload.asset_id"
          "version.$"   = "$.Payload.version"
          "file_name.$" = "$.Payload.file_name"
        }
        ResultPath = "$.asset"
        Next       = "NotificarSupervisor"
      }
      NotificarSupervisor = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.render_final_aprobaciones.arn
          Subject     = "Nuevo asset de Render Final para revision"
          "Message.$" = "States.Format('Asset listo para revision: {} (subido por {})', $.asset.file_name, $.uploaded_by)"
        }
        ResultPath = null
        Next       = "EvaluarDecision"
      }
      EvaluarDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.decision"
            StringEquals = "aprobado"
            Next         = "GrabarAprobado"
          },
          {
            Variable     = "$.decision"
            StringEquals = "rechazado"
            Next         = "GrabarRechazado"
          }
        ]
        Default = "DecisionInvalida"
      }
      GrabarAprobado = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = data.aws_dynamodb_table.render_final_metadata.name
          Key = {
            asset_id = { "S.$" = "$.asset.asset_id" }
            version  = { "S.$" = "$.asset.version" }
          }
          UpdateExpression = "SET approval_status = :estado, reviewed_by = :revisor, reviewed_at = :momento"
          ExpressionAttributeValues = {
            ":estado"  = { "S" = "aprobado" }
            ":revisor" = { "S.$" = "$.reviewed_by" }
            ":momento" = { "S.$" = "$$.State.EnteredTime" }
          }
        }
        ResultPath = null
        Next       = "NotificarAprobado"
      }
      NotificarAprobado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.render_final_aprobaciones.arn
          Subject     = "Asset de Render Final aprobado"
          "Message.$" = "States.Format('Aprobado: {}. El supervisor debe enviarlo a la cola render-queue con el comando documentado.', $.asset.file_name)"
        }
        End = true
      }
      GrabarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = data.aws_dynamodb_table.render_final_metadata.name
          Key = {
            asset_id = { "S.$" = "$.asset.asset_id" }
            version  = { "S.$" = "$.asset.version" }
          }
          UpdateExpression = "SET approval_status = :estado, reviewed_by = :revisor, reviewed_at = :momento"
          ExpressionAttributeValues = {
            ":estado"  = { "S" = "rechazado" }
            ":revisor" = { "S.$" = "$.reviewed_by" }
            ":momento" = { "S.$" = "$$.State.EnteredTime" }
          }
        }
        ResultPath = null
        Next       = "NotificarRechazado"
      }
      NotificarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.render_final_aprobaciones.arn
          Subject     = "Asset de Render Final rechazado"
          "Message.$" = "States.Format('Rechazado: {}. Vuelve al artista para correccion.', $.asset.file_name)"
        }
        End = true
      }
      DecisionInvalida = {
        Type  = "Fail"
        Error = "DecisionInvalida"
        Cause = "El campo decision debe ser aprobado o rechazado"
      }
    }
  })
}

# MP4 liviano para revision: reutiliza el modulo video (Lambda FFmpeg).
# Deja el resultado en vfx-dailies/render-final/
module "render_final_video" {
  source           = "../modules/video"
  departamento     = "render-final"
  dailies_bucket   = "vfx-dailies"
  ffmpeg_layer_arn = aws_lambda_layer_version.ffmpeg.arn
}