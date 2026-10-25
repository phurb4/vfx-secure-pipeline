resource "aws_iam_role" "lambda_role" {
  name = "vfx-lambda-${var.departamento}-imagen-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_policy" {
  name = "vfx-lambda-${var.departamento}-imagen-s3-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::vfx-${var.departamento}-output/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.dailies_bucket}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "logs_policy" {
  name = "vfx-lambda-${var.departamento}-imagen-logs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/vfx-${var.departamento}-imagen-dailies:*"
      }
    ]
  })
}

data "archive_file" "imagen_dailies_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/function-${var.departamento}.zip"
}

resource "aws_lambda_function" "imagen_dailies" {
  function_name = "vfx-${var.departamento}-imagen-dailies"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.imagen_dailies_zip.output_path
  source_code_hash = data.archive_file.imagen_dailies_zip.output_base64sha256

  environment {
    variables = {
      DAILIES_BUCKET = var.dailies_bucket
      DEPT_PREFIX    = var.departamento
      S3_ENDPOINT_URL = var.s3_endpoint
    }
  }
}

resource "aws_lambda_permission" "allow_s3_output" {
  statement_id  = "AllowExecutionFromS3Output"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.imagen_dailies.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::vfx-${var.departamento}-output"
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "output_trigger" {
  bucket = "vfx-${var.departamento}-output"

  lambda_function {
    lambda_function_arn = aws_lambda_function.imagen_dailies.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".png"
  }

  depends_on = [aws_lambda_permission.allow_s3_output]
}