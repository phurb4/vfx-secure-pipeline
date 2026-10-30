# =====================================================================
# HORARIO LABORAL + OVERTIME POR DEPARTAMENTO (sesion del 23 de octubre de 2026)
# =====================================================================
# Diseno: IAM niega por defecto todo lo que no tiene un Allow. Entonces:
#  - Las "politicas de trabajo" se CREAN aca pero NO se adjuntan con Terraform.
#    Las adjunta/saca la Lambda "vfx-horario" segun el horario, directamente a
#    cada USUARIO (sin grupos: la SCP de la cuenta niega iam:CreateGroup).
#    La Lambda decide a quien por las etiquetas "rol" y "departamento".
#  - Artista/Lead/overtime: con la politica de trabajo puesta pueden trabajar;
#    sin ella, IAM les niega todo (no hace falta ningun Deny de horario).
#  - Supervisores: la politica "exigir MFA" se adjunta fuera de horario.
#  - Overtime: el supervisor etiqueta al usuario con overtime=si; la Lambda
#    adjunta la politica de overtime del departamento a TODOS los artistas y
#    leads de ese departamento de 09:00 a 18:00, pero la politica solo vale
#    para quien tenga la etiqueta overtime=si (quitar la etiqueta revoca al
#    instante). Los lunes la Lambda borra la etiqueta a todos.
# Horarios en UTC. Buenos Aires = UTC-3 todo el anio (sin horario de verano):
#   09:00 Buenos Aires = 12:00 UTC  |  18:00 Buenos Aires = 21:00 UTC
# =====================================================================

variable "iam_endpoint" {
  description = "Endpoint de IAM que usa la Lambda de horario. En Floci: http://localhost:4566. En AWS real: poner vacio (\"\")."
  type        = string
  default     = ""
}

locals {
  horario_departamentos = [
    "modelado",
    "texturing",
    "rigging",
    "animation",
    "fx",
    "compositing",
    "render-final",
  ]

  horario_reglas = {
    semana-abrir    = { cron = "cron(0 12 ? * MON-FRI *)", conjunto = "semana", accion = "abrir" }
    semana-cerrar   = { cron = "cron(0 21 ? * MON-FRI *)", conjunto = "semana", accion = "cerrar" }
    overtime-abrir  = { cron = "cron(0 12 * * ? *)", conjunto = "overtime", accion = "abrir" }
    overtime-cerrar = { cron = "cron(0 21 * * ? *)", conjunto = "overtime", accion = "cerrar" }
    vaciar-lunes    = { cron = "cron(0 9 ? * MON *)", conjunto = "vaciar", accion = "ejecutar" }
  }
}

# ---------------------------------------------------------------------
# POLITICA DE TRABAJO DE ARTISTA Y LEAD (identica para los dos roles)
# La adjunta la Lambda a las 09:00 y la saca a las 18:00, lunes a viernes.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "trabajo_artista_lead" {
  statement {
    sid    = "ABACAccesoSoloASuDepartamentoS3"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
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
    ]
    resources = [
      "arn:aws:dynamodb:*:*:table/vfx-$${aws:PrincipalTag/departamento}-metadata",
    ]
  }
}

resource "aws_iam_policy" "trabajo_artista_lead" {
  name   = "vfx-trabajo-artista-lead-policy"
  policy = data.aws_iam_policy_document.trabajo_artista_lead.json
}

# ---------------------------------------------------------------------
# POLITICAS DE OVERTIME: una por departamento
# La politica de cada departamento apunta SOLO a los recursos de su
# departamento y exige DOS etiquetas del usuario: departamento igual al
# del recurso y overtime=si. Asi, aunque la Lambda la adjunte a todos los
# artistas y leads del departamento durante el dia, solo funciona para
# quien el supervisor etiqueto con overtime=si.
# Horario: la Lambda adjunta la politica a las 09:00 y la saca a las 18:00,
# TODOS los dias (incluye sabado y domingo).
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "overtime_trabajo" {
  for_each = toset(local.horario_departamentos)

  statement {
    sid    = "S3SoloSuDepartamento"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::vfx-${each.key}-input",
      "arn:aws:s3:::vfx-${each.key}-input/*",
      "arn:aws:s3:::vfx-${each.key}-output",
      "arn:aws:s3:::vfx-${each.key}-output/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/departamento"
      values   = [each.key]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/overtime"
      values   = ["si"]
    }
  }

  statement {
    sid       = "DailiesListarSoloSuCarpeta"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::vfx-dailies"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.key}/*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/departamento"
      values   = [each.key]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/overtime"
      values   = ["si"]
    }
  }

  statement {
    sid    = "DailiesObjetosSoloSuCarpeta"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["arn:aws:s3:::vfx-dailies/${each.key}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/departamento"
      values   = [each.key]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/overtime"
      values   = ["si"]
    }
  }

  statement {
    sid    = "DynamoDBSoloSuDepartamento"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
    ]
    resources = ["arn:aws:dynamodb:*:*:table/vfx-${each.key}-metadata"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/departamento"
      values   = [each.key]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/overtime"
      values   = ["si"]
    }
  }
}

resource "aws_iam_policy" "overtime_trabajo" {
  for_each = toset(local.horario_departamentos)
  name     = "vfx-overtime-${each.key}-trabajo-policy"
  policy   = data.aws_iam_policy_document.overtime_trabajo[each.key].json
}

# ---------------------------------------------------------------------
# SUPERVISORES: MFA obligatorio fuera de horario
# La Lambda adjunta esta politica a las 18:00 y la saca a las 09:00 (solo
# lunes a viernes: el fin de semana queda puesta todo el tiempo). Cubre
# tambien antes de las 09:00, que el diseno anterior no cubria.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "supervisor_mfa" {
  statement {
    sid       = "ExigirMFAFueraDeHorario"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "supervisor_mfa" {
  name   = "vfx-supervisor-mfa-fuera-de-horario-policy"
  policy = data.aws_iam_policy_document.supervisor_mfa.json
}

# ---------------------------------------------------------------------
# SUPERVISORES: permiso para sumar y quitar gente de overtime
# (manual, cuando hace falta). Siempre adjuntas. Sumar = poner la etiqueta
# overtime=si al usuario; quitar = borrar esa etiqueta. Solo se puede tocar
# la clave "overtime" (nunca "departamento" ni "rol").
#  - Supervisor de departamento: SOLO usuarios de su propio departamento.
#  - Supervisor VFX general: usuarios de cualquier departamento.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "supervisor_departamento_overtime" {
  statement {
    sid       = "PonerOvertimeSoloEnSuDepartamento"
    effect    = "Allow"
    actions   = ["iam:TagUser"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/departamento"
      values   = ["$${aws:PrincipalTag/departamento}"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["overtime"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/overtime"
      values   = ["si"]
    }
  }

  statement {
    sid       = "QuitarOvertimeSoloEnSuDepartamento"
    effect    = "Allow"
    actions   = ["iam:UntagUser"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/departamento"
      values   = ["$${aws:PrincipalTag/departamento}"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["overtime"]
    }
  }

  statement {
    sid       = "VerEtiquetasDeSuDepartamento"
    effect    = "Allow"
    actions   = ["iam:ListUserTags", "iam:GetUser"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/departamento"
      values   = ["$${aws:PrincipalTag/departamento}"]
    }
  }

  statement {
    sid       = "ListarUsuarios"
    effect    = "Allow"
    actions   = ["iam:ListUsers"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "supervisor_departamento_overtime" {
  name   = "vfx-supervisor-departamento-overtime-policy"
  policy = data.aws_iam_policy_document.supervisor_departamento_overtime.json
}

data "aws_iam_policy_document" "supervisor_general_overtime" {
  statement {
    sid       = "PonerOvertimeEnCualquierDepartamento"
    effect    = "Allow"
    actions   = ["iam:TagUser"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["overtime"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/overtime"
      values   = ["si"]
    }
  }

  statement {
    sid       = "QuitarOvertimeEnCualquierDepartamento"
    effect    = "Allow"
    actions   = ["iam:UntagUser"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["overtime"]
    }
  }

  statement {
    sid       = "VerUsuariosYEtiquetas"
    effect    = "Allow"
    actions   = ["iam:ListUsers", "iam:ListUserTags", "iam:GetUser"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "supervisor_general_overtime" {
  name   = "vfx-supervisor-general-overtime-policy"
  policy = data.aws_iam_policy_document.supervisor_general_overtime.json
}

# ---------------------------------------------------------------------
# LAMBDA vfx-horario: adjunta/saca politicas a cada usuario segun el
# horario (leyendo sus etiquetas) y borra la etiqueta overtime los lunes.
# ---------------------------------------------------------------------
resource "aws_iam_role" "lambda_overtime_role" {
  name = "vfx-lambda-overtime-role"

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

locals {
  horario_politicas_permitidas = concat(
    [
      aws_iam_policy.trabajo_artista_lead.arn,
      aws_iam_policy.supervisor_mfa.arn,
    ],
    [for p in aws_iam_policy.overtime_trabajo : p.arn],
  )

  # La Lambda lee las etiquetas "rol" y "departamento" de cada usuario.
  horario_config = {
    semana = {
      trabajo = {
        "artista" = aws_iam_policy.trabajo_artista_lead.arn
        "lead"    = aws_iam_policy.trabajo_artista_lead.arn
      }
      mfa = {
        "supervisor-departamento" = aws_iam_policy.supervisor_mfa.arn
        "supervisor-vfx-general"  = aws_iam_policy.supervisor_mfa.arn
      }
    }
    overtime = {
      roles = ["artista", "lead"]
      politicas = {
        for d in local.horario_departamentos : d => aws_iam_policy.overtime_trabajo[d].arn
      }
    }
  }
}

data "aws_iam_policy_document" "lambda_horario_permisos" {
  statement {
    sid       = "ListarUsuarios"
    effect    = "Allow"
    actions   = ["iam:ListUsers"]
    resources = ["*"]
  }

  statement {
    sid       = "LeerEtiquetasYPoliticasDeLosUsuarios"
    effect    = "Allow"
    actions   = ["iam:ListUserTags", "iam:ListAttachedUserPolicies"]
    resources = ["arn:aws:iam::*:user/*"]
  }

  statement {
    sid       = "AdjuntarYSacarSoloLasPoliticasDeHorario"
    effect    = "Allow"
    actions   = ["iam:AttachUserPolicy", "iam:DetachUserPolicy"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = local.horario_politicas_permitidas
    }
  }

  statement {
    sid       = "BorrarSoloLaEtiquetaOvertime"
    effect    = "Allow"
    actions   = ["iam:UntagUser"]
    resources = ["arn:aws:iam::*:user/*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["overtime"]
    }
  }

  statement {
    sid       = "EscribirSoloSusLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/vfx-horario:*"]
  }
}

resource "aws_iam_role_policy" "lambda_horario_permisos" {
  name   = "vfx-lambda-horario-permisos"
  role   = aws_iam_role.lambda_overtime_role.id
  policy = data.aws_iam_policy_document.lambda_horario_permisos.json
}

data "archive_file" "lambda_horario_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_horario.zip"

  source {
    content  = <<EOF
import json
import os

import boto3

CONFIG = json.loads(os.environ["CONFIG"])


def cliente_iam():
    endpoint = os.environ.get("IAM_ENDPOINT") or None
    return boto3.client("iam", endpoint_url=endpoint, region_name="us-east-1")


def listar_personal(iam):
    personal = []
    for pagina in iam.get_paginator("list_users").paginate():
        for usuario in pagina["Users"]:
            nombre = usuario["UserName"]
            etiquetas = {}
            for p in iam.get_paginator("list_user_tags").paginate(UserName=nombre):
                for etiqueta in p["Tags"]:
                    etiquetas[etiqueta["Key"]] = etiqueta["Value"]
            personal.append({"nombre": nombre, "etiquetas": etiquetas})
    return personal


def politicas_adjuntas(iam, usuario):
    arns = set()
    for pagina in iam.get_paginator("list_attached_user_policies").paginate(UserName=usuario):
        for politica in pagina["AttachedPolicies"]:
            arns.add(politica["PolicyArn"])
    return arns


def aplicar(iam, usuario, arn, adjuntar):
    puesta = arn in politicas_adjuntas(iam, usuario)
    if adjuntar and not puesta:
        iam.attach_user_policy(UserName=usuario, PolicyArn=arn)
        return usuario + ": adjuntada"
    if not adjuntar and puesta:
        iam.detach_user_policy(UserName=usuario, PolicyArn=arn)
        return usuario + ": sacada"
    return usuario + ": sin cambios"


def vaciar(iam, usuario):
    iam.untag_user(UserName=usuario, TagKeys=["overtime"])
    return usuario + ": etiqueta overtime borrada"


def armar_tareas(personal, conjunto, accion):
    abrir = accion == "abrir"
    tareas = []
    for u in personal:
        rol = u["etiquetas"].get("rol")
        depto = u["etiquetas"].get("departamento")
        if conjunto == "semana":
            if rol in CONFIG["semana"]["trabajo"]:
                tareas.append(("aplicar", u["nombre"], CONFIG["semana"]["trabajo"][rol], abrir))
            if rol in CONFIG["semana"]["mfa"]:
                tareas.append(("aplicar", u["nombre"], CONFIG["semana"]["mfa"][rol], not abrir))
        elif conjunto == "overtime":
            if rol in CONFIG["overtime"]["roles"] and depto in CONFIG["overtime"]["politicas"]:
                tareas.append(("aplicar", u["nombre"], CONFIG["overtime"]["politicas"][depto], abrir))
        elif conjunto == "vaciar":
            if "overtime" in u["etiquetas"]:
                tareas.append(("vaciar", u["nombre"], None, None))
    return tareas


def handler(event, context):
    iam = cliente_iam()
    conjunto = event["conjunto"]
    accion = event["accion"]
    resultado = []
    errores = []

    for tipo, usuario, arn, adjuntar in armar_tareas(listar_personal(iam), conjunto, accion):
        try:
            if tipo == "vaciar":
                resultado.append(vaciar(iam, usuario))
            else:
                resultado.append(aplicar(iam, usuario, arn, adjuntar))
        except Exception as e:
            errores.append(usuario + " -> " + str(e))

    print(json.dumps({"conjunto": conjunto, "accion": accion, "resultado": resultado, "errores": errores}))
    if errores:
        raise Exception("Fallaron " + str(len(errores)) + " cambios: " + "; ".join(errores))
    return {"conjunto": conjunto, "accion": accion, "resultado": resultado}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "horario" {
  function_name    = "vfx-horario"
  role             = aws_iam_role.lambda_overtime_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.lambda_horario_zip.output_path
  source_code_hash = data.archive_file.lambda_horario_zip.output_base64sha256

  environment {
    variables = {
      CONFIG       = jsonencode(local.horario_config)
      IAM_ENDPOINT = var.iam_endpoint
    }
  }
}

# ---------------------------------------------------------------------
# REGLAS DE EVENTBRIDGE (todas en UTC, ver cabecera)
# ---------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "horario" {
  for_each            = local.horario_reglas
  name                = "vfx-horario-${each.key}"
  description         = "Horario: ${each.value.conjunto} / ${each.value.accion}"
  schedule_expression = each.value.cron
}

resource "aws_cloudwatch_event_target" "horario" {
  for_each = local.horario_reglas
  rule     = aws_cloudwatch_event_rule.horario[each.key].name
  arn      = aws_lambda_function.horario.arn
  input = jsonencode({
    conjunto = each.value.conjunto
    accion   = each.value.accion
  })
}

resource "aws_lambda_permission" "horario" {
  for_each      = local.horario_reglas
  statement_id  = "AllowEventBridgeHorario-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.horario.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.horario[each.key].arn
}

# ---------------------------------------------------------------------
# USUARIO DE PRUEBA DE RENDER FINAL (para probar ABAC y overtime de ese depto)
# ---------------------------------------------------------------------
resource "aws_iam_user" "prueba_artista_render_final" {
  name = "prueba-artista-render-final"

  tags = {
    departamento = "render-final"
    rol          = "artista"
    proyecto     = "pipeline-vfx"
  }
}