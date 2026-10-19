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
    sns           = "http://localhost:4566"
    iam           = "http://localhost:4566"
    dynamodb      = "http://localhost:4566"
    lambda        = "http://localhost:4566"
    stepfunctions = "http://localhost:4566"
    sts           = "http://localhost:4566"
    s3            = "http://localhost:4566"
  }
}

variable "alert_email" {
  type      = string
  sensitive = true
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_dynamodb_table" "modelado_metadata" {
  name = "vfx-modelado-metadata"
}

data "aws_dynamodb_table" "texturing_metadata" {
  name = "vfx-texturing-metadata"
}

data "aws_dynamodb_table" "rigging_metadata" {
  name = "vfx-rigging-metadata"
}

data "aws_dynamodb_table" "animation_metadata" {
  name = "vfx-animation-metadata"
}

data "aws_dynamodb_table" "fx_metadata" {
  name = "vfx-fx-metadata"
}

data "aws_dynamodb_table" "compositing_metadata" {
  name = "vfx-compositing-metadata"
}

resource "aws_sns_topic" "modelado_aprobaciones" {
  name = "vfx-modelado-aprobaciones"

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_sns_topic_subscription" "modelado_supervisor_email" {
  topic_arn = aws_sns_topic.modelado_aprobaciones.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_iam_role" "lambda_modelado_role" {
  name = "vfx-lambda-modelado-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_role_policy" "lambda_modelado_policy" {
  name = "vfx-lambda-modelado-policy"
  role = aws_iam_role.lambda_modelado_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = data.aws_dynamodb_table.modelado_metadata.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.modelado_aprobaciones.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/vfx-modelado-version-namer:*"
      }
    ]
  })
}

data "archive_file" "version_namer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/version_namer.py"
  output_path = "${path.module}/version_namer.zip"
}

resource "aws_lambda_function" "modelado_version_namer" {
  function_name    = "vfx-modelado-version-namer"
  role             = aws_iam_role.lambda_modelado_role.arn
  handler          = "version_namer.lambda_handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.version_namer_zip.output_path
  source_code_hash = data.archive_file.version_namer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = data.aws_dynamodb_table.modelado_metadata.name
      DEPT_PREFIX = "MOD"
    }
  }

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_role" "sfn_modelado_role" {
  name = "vfx-sfn-modelado-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

resource "aws_iam_role_policy" "sfn_modelado_policy" {
  name = "vfx-sfn-modelado-policy"
  role = aws_iam_role.sfn_modelado_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.modelado_version_namer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.modelado_aprobaciones.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "modelado_aprobacion" {
  name     = "vfx-modelado-aprobacion"
  role_arn = aws_iam_role.sfn_modelado_role.arn

  definition = jsonencode({
    Comment = "Flujo de aprobacion del departamento de Modelado"
    StartAt = "AsignarVersion"
    States = {
      AsignarVersion = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.modelado_version_namer.arn
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
          TopicArn    = aws_sns_topic.modelado_aprobaciones.arn
          Subject     = "Nuevo asset de Modelado para revision"
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
          TableName = data.aws_dynamodb_table.modelado_metadata.name
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
          TopicArn    = aws_sns_topic.modelado_aprobaciones.arn
          Subject     = "Asset de Modelado aprobado"
          "Message.$" = "States.Format('Aprobado: {}. Listo para pasar al siguiente departamento.', $.asset.file_name)"
        }
        End = true
      }

      GrabarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = data.aws_dynamodb_table.modelado_metadata.name
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
          TopicArn    = aws_sns_topic.modelado_aprobaciones.arn
          Subject     = "Asset de Modelado rechazado"
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

  tags = {
    departamento = "modelado"
    proyecto     = "pipeline-vfx"
  }
}

# --- Bucket donde vive el zip de la capa de FFmpeg (por el limite de 50 MB) ---
resource "aws_s3_bucket" "vfx_lambda_layers" {
  bucket = "vfx-lambda-layers"
}

# --- Subida del zip de la capa al bucket ---
resource "aws_s3_object" "ffmpeg_layer_zip" {
  bucket      = aws_s3_bucket.vfx_lambda_layers.id
  key         = "ffmpeg-layer.zip"
  source      = "${path.module}/layers/ffmpeg-layer.zip"
  source_hash = filemd5("${path.module}/layers/ffmpeg-layer.zip")
}

# --- La capa de FFmpeg, publicada desde el objeto de S3 ---
resource "aws_lambda_layer_version" "ffmpeg" {
  layer_name          = "ffmpeg"
  s3_bucket           = aws_s3_bucket.vfx_lambda_layers.id
  s3_key              = aws_s3_object.ffmpeg_layer_zip.key
  compatible_runtimes = ["python3.12"]
}

module "modelado_imagen_dailies" {
  source         = "../modules/imagen-dailies"
  departamento   = "modelado"
  dailies_bucket = "vfx-dailies"
}

module "texturing_imagen_dailies" {
  source         = "../modules/imagen-dailies"
  departamento   = "texturing"
  dailies_bucket = "vfx-dailies"
}

module "rigging_imagen_dailies" {
  source         = "../modules/imagen-dailies"
  departamento   = "rigging"
  dailies_bucket = "vfx-dailies"
}

resource "aws_sns_topic" "texturing_aprobaciones" {
  name = "vfx-texturing-aprobaciones"
}

resource "aws_sns_topic_subscription" "texturing_supervisor_email" {
  topic_arn = aws_sns_topic.texturing_aprobaciones.arn
  protocol  = "email"
  endpoint  = "supervisor@vfxstudio.com"
}

resource "aws_iam_role" "lambda_texturing_role" {
  name = "vfx-lambda-texturing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_texturing_policy" {
  name = "vfx-lambda-texturing-policy"
  role = aws_iam_role.lambda_texturing_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = data.aws_dynamodb_table.texturing_metadata.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "texturing_version_namer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/version_namer.py"
  output_path = "${path.module}/texturing_version_namer.zip"
}

resource "aws_lambda_function" "texturing_version_namer" {
  function_name = "vfx-texturing-version-namer"
  role          = aws_iam_role.lambda_texturing_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.texturing_version_namer_zip.output_path
  source_code_hash = data.archive_file.texturing_version_namer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = data.aws_dynamodb_table.texturing_metadata.name
      DEPT_PREFIX = "TEX"
    }
  }
}

resource "aws_iam_role" "sfn_texturing_role" {
  name = "vfx-sfn-texturing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_texturing_policy" {
  name = "vfx-sfn-texturing-policy"
  role = aws_iam_role.sfn_texturing_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.texturing_version_namer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.texturing_aprobaciones.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "texturing_aprobacion" {
  name     = "vfx-texturing-aprobacion"
  role_arn = aws_iam_role.sfn_texturing_role.arn

  definition = jsonencode({
    Comment = "Flujo de aprobacion Texturing"
    StartAt = "AsignarVersion"
    States = {
      AsignarVersion = {
        Type     = "Task"
        Resource = aws_lambda_function.texturing_version_namer.arn
        Next     = "NotificarSupervisor"
      }
      NotificarSupervisor = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.texturing_aprobaciones.arn
          "Message.$" = "$.mensaje"
        }
        Next = "EvaluarDecision"
      }
      EvaluarDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.decision"
            StringEquals = "aprobado"
            Next         = "NotificarAprobado"
          },
          {
            Variable     = "$.decision"
            StringEquals = "rechazado"
            Next         = "NotificarRechazado"
          }
        ]
        Default = "DecisionInvalida"
      }
      NotificarAprobado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.texturing_aprobaciones.arn
          Message  = "Asset aprobado en Texturing"
        }
        End = true
      }
      NotificarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.texturing_aprobaciones.arn
          Message  = "Asset rechazado en Texturing"
        }
        End = true
      }
      DecisionInvalida = {
        Type  = "Fail"
        Error = "DecisionInvalida"
      }
    }
  })
}

resource "aws_sns_topic" "rigging_aprobaciones" {
  name = "vfx-rigging-aprobaciones"
}

resource "aws_sns_topic_subscription" "rigging_supervisor_email" {
  topic_arn = aws_sns_topic.rigging_aprobaciones.arn
  protocol  = "email"
  endpoint  = "supervisor@vfxstudio.com"
}

resource "aws_iam_role" "lambda_rigging_role" {
  name = "vfx-lambda-rigging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_rigging_policy" {
  name = "vfx-lambda-rigging-policy"
  role = aws_iam_role.lambda_rigging_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = data.aws_dynamodb_table.rigging_metadata.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "rigging_version_namer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/version_namer.py"
  output_path = "${path.module}/rigging_version_namer.zip"
}

resource "aws_lambda_function" "rigging_version_namer" {
  function_name = "vfx-rigging-version-namer"
  role          = aws_iam_role.lambda_rigging_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.rigging_version_namer_zip.output_path
  source_code_hash = data.archive_file.rigging_version_namer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = data.aws_dynamodb_table.rigging_metadata.name
      DEPT_PREFIX = "RIG"
    }
  }
}

resource "aws_iam_role" "sfn_rigging_role" {
  name = "vfx-sfn-rigging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_rigging_policy" {
  name = "vfx-sfn-rigging-policy"
  role = aws_iam_role.sfn_rigging_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.rigging_version_namer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.rigging_aprobaciones.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "rigging_aprobacion" {
  name     = "vfx-rigging-aprobacion"
  role_arn = aws_iam_role.sfn_rigging_role.arn

  definition = jsonencode({
    Comment = "Flujo de aprobacion Rigging"
    StartAt = "AsignarVersion"
    States = {
      AsignarVersion = {
        Type     = "Task"
        Resource = aws_lambda_function.rigging_version_namer.arn
        Next     = "NotificarSupervisor"
      }
      NotificarSupervisor = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.rigging_aprobaciones.arn
          "Message.$" = "$.mensaje"
        }
        Next = "EvaluarDecision"
      }
      EvaluarDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.decision"
            StringEquals = "aprobado"
            Next         = "NotificarAprobado"
          },
          {
            Variable     = "$.decision"
            StringEquals = "rechazado"
            Next         = "NotificarRechazado"
          }
        ]
        Default = "DecisionInvalida"
      }
      NotificarAprobado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.rigging_aprobaciones.arn
          Message  = "Asset aprobado en Rigging"
        }
        End = true
      }
      NotificarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.rigging_aprobaciones.arn
          Message  = "Asset rechazado en Rigging"
        }
        End = true
      }
      DecisionInvalida = {
        Type  = "Fail"
        Error = "DecisionInvalida"
      }
    }
  })
}

resource "aws_sns_topic" "animation_aprobaciones" {
  name = "vfx-animation-aprobaciones"
}

resource "aws_sns_topic_subscription" "animation_supervisor_email" {
  topic_arn = aws_sns_topic.animation_aprobaciones.arn
  protocol  = "email"
  endpoint  = "supervisor@vfxstudio.com"
}

resource "aws_iam_role" "lambda_animation_role" {
  name = "vfx-lambda-animation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_animation_policy" {
  name = "vfx-lambda-animation-policy"
  role = aws_iam_role.lambda_animation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = data.aws_dynamodb_table.animation_metadata.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "animation_version_namer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/version_namer.py"
  output_path = "${path.module}/animation_version_namer.zip"
}

resource "aws_lambda_function" "animation_version_namer" {
  function_name = "vfx-animation-version-namer"
  role          = aws_iam_role.lambda_animation_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.animation_version_namer_zip.output_path
  source_code_hash = data.archive_file.animation_version_namer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = data.aws_dynamodb_table.animation_metadata.name
      DEPT_PREFIX = "ANIM"
    }
  }
}

resource "aws_iam_role" "sfn_animation_role" {
  name = "vfx-sfn-animation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_animation_policy" {
  name = "vfx-sfn-animation-policy"
  role = aws_iam_role.sfn_animation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.animation_version_namer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.animation_aprobaciones.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "animation_aprobacion" {
  name     = "vfx-animation-aprobacion"
  role_arn = aws_iam_role.sfn_animation_role.arn

  definition = jsonencode({
    Comment = "Flujo de aprobacion Animation"
    StartAt = "AsignarVersion"
    States = {
      AsignarVersion = {
        Type     = "Task"
        Resource = aws_lambda_function.animation_version_namer.arn
        Next     = "NotificarSupervisor"
      }
      NotificarSupervisor = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.animation_aprobaciones.arn
          "Message.$" = "$.mensaje"
        }
        Next = "EvaluarDecision"
      }
      EvaluarDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.decision"
            StringEquals = "aprobado"
            Next         = "NotificarAprobado"
          },
          {
            Variable     = "$.decision"
            StringEquals = "rechazado"
            Next         = "NotificarRechazado"
          }
        ]
        Default = "DecisionInvalida"
      }
      NotificarAprobado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.animation_aprobaciones.arn
          Message  = "Asset aprobado en Animation"
        }
        End = true
      }
      NotificarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.animation_aprobaciones.arn
          Message  = "Asset rechazado en Animation"
        }
        End = true
      }
      DecisionInvalida = {
        Type  = "Fail"
        Error = "DecisionInvalida"
      }
    }
  })
}

module "animation_video" {
  source           = "../modules/video"
  departamento     = "animation"
  dailies_bucket   = "vfx-dailies"
  ffmpeg_layer_arn = aws_lambda_layer_version.ffmpeg.arn
}

resource "aws_sns_topic" "fx_aprobaciones" {
  name = "vfx-fx-aprobaciones"
}

resource "aws_sns_topic_subscription" "fx_supervisor_email" {
  topic_arn = aws_sns_topic.fx_aprobaciones.arn
  protocol  = "email"
  endpoint  = "supervisor@vfxstudio.com"
}

resource "aws_iam_role" "lambda_fx_role" {
  name = "vfx-lambda-fx-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_fx_policy" {
  name = "vfx-lambda-fx-policy"
  role = aws_iam_role.lambda_fx_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = data.aws_dynamodb_table.fx_metadata.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "fx_version_namer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/version_namer.py"
  output_path = "${path.module}/fx_version_namer.zip"
}

resource "aws_lambda_function" "fx_version_namer" {
  function_name = "vfx-fx-version-namer"
  role          = aws_iam_role.lambda_fx_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.fx_version_namer_zip.output_path
  source_code_hash = data.archive_file.fx_version_namer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = data.aws_dynamodb_table.fx_metadata.name
      DEPT_PREFIX = "FX"
    }
  }
}

resource "aws_iam_role" "sfn_fx_role" {
  name = "vfx-sfn-fx-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_fx_policy" {
  name = "vfx-sfn-fx-policy"
  role = aws_iam_role.sfn_fx_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.fx_version_namer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.fx_aprobaciones.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "fx_aprobacion" {
  name     = "vfx-fx-aprobacion"
  role_arn = aws_iam_role.sfn_fx_role.arn

  definition = jsonencode({
    Comment = "Flujo de aprobacion FX"
    StartAt = "AsignarVersion"
    States = {
      AsignarVersion = {
        Type     = "Task"
        Resource = aws_lambda_function.fx_version_namer.arn
        Next     = "NotificarSupervisor"
      }
      NotificarSupervisor = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.fx_aprobaciones.arn
          "Message.$" = "$.mensaje"
        }
        Next = "EvaluarDecision"
      }
      EvaluarDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.decision"
            StringEquals = "aprobado"
            Next         = "NotificarAprobado"
          },
          {
            Variable     = "$.decision"
            StringEquals = "rechazado"
            Next         = "NotificarRechazado"
          }
        ]
        Default = "DecisionInvalida"
      }
      NotificarAprobado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.fx_aprobaciones.arn
          Message  = "Asset aprobado en FX"
        }
        End = true
      }
      NotificarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.fx_aprobaciones.arn
          Message  = "Asset rechazado en FX"
        }
        End = true
      }
      DecisionInvalida = {
        Type  = "Fail"
        Error = "DecisionInvalida"
      }
    }
  })
}

module "fx_video" {
  source           = "../modules/video"
  departamento     = "fx"
  dailies_bucket   = "vfx-dailies"
  ffmpeg_layer_arn = aws_lambda_layer_version.ffmpeg.arn
}

resource "aws_sns_topic" "compositing_aprobaciones" {
  name = "vfx-compositing-aprobaciones"
}

resource "aws_sns_topic_subscription" "compositing_supervisor_email" {
  topic_arn = aws_sns_topic.compositing_aprobaciones.arn
  protocol  = "email"
  endpoint  = "supervisor@vfxstudio.com"
}

resource "aws_iam_role" "lambda_compositing_role" {
  name = "vfx-lambda-compositing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_compositing_policy" {
  name = "vfx-lambda-compositing-policy"
  role = aws_iam_role.lambda_compositing_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = data.aws_dynamodb_table.compositing_metadata.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "archive_file" "compositing_version_namer_zip" {
  type        = "zip"
  source_file = "${path.module}/src/version_namer.py"
  output_path = "${path.module}/compositing_version_namer.zip"
}

resource "aws_lambda_function" "compositing_version_namer" {
  function_name = "vfx-compositing-version-namer"
  role          = aws_iam_role.lambda_compositing_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename         = data.archive_file.compositing_version_namer_zip.output_path
  source_code_hash = data.archive_file.compositing_version_namer_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = data.aws_dynamodb_table.compositing_metadata.name
      DEPT_PREFIX = "COMP"
    }
  }
}

resource "aws_iam_role" "sfn_compositing_role" {
  name = "vfx-sfn-compositing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_compositing_policy" {
  name = "vfx-sfn-compositing-policy"
  role = aws_iam_role.sfn_compositing_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.compositing_version_namer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.compositing_aprobaciones.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "compositing_aprobacion" {
  name     = "vfx-compositing-aprobacion"
  role_arn = aws_iam_role.sfn_compositing_role.arn

  definition = jsonencode({
    Comment = "Flujo de aprobacion Compositing"
    StartAt = "AsignarVersion"
    States = {
      AsignarVersion = {
        Type     = "Task"
        Resource = aws_lambda_function.compositing_version_namer.arn
        Next     = "NotificarSupervisor"
      }
      NotificarSupervisor = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.compositing_aprobaciones.arn
          "Message.$" = "$.mensaje"
        }
        Next = "EvaluarDecision"
      }
      EvaluarDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.decision"
            StringEquals = "aprobado"
            Next         = "NotificarAprobado"
          },
          {
            Variable     = "$.decision"
            StringEquals = "rechazado"
            Next         = "NotificarRechazado"
          }
        ]
        Default = "DecisionInvalida"
      }
      NotificarAprobado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.compositing_aprobaciones.arn
          Message  = "Asset aprobado en Compositing"
        }
        End = true
      }
      NotificarRechazado = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.compositing_aprobaciones.arn
          Message  = "Asset rechazado en Compositing"
        }
        End = true
      }
      DecisionInvalida = {
        Type  = "Fail"
        Error = "DecisionInvalida"
      }
    }
  })
}

module "compositing_video" {
  source           = "../modules/video"
  departamento     = "compositing"
  dailies_bucket   = "vfx-dailies"
  ffmpeg_layer_arn = aws_lambda_layer_version.ffmpeg.arn
}
