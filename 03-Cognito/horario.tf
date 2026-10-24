# =====================================================================
# HORARIO LABORAL + OVERTIME POR DEPARTAMENTO (sesion del 23 de octubre de 2026)
# =====================================================================
# Diseno: IAM niega por defecto todo lo que no tiene un Allow. Entonces:
#  - Las "politicas de trabajo" se CREAN aca pero NO se adjuntan con Terraform.
#    Las adjunta/saca la Lambda "vfx-horario" segun el horario (Terraform solo
#    las crea; si las adjuntara, cada plan veria diferencias contra lo que la
#    Lambda hizo de noche).
#  - Artista/Lead/overtime: con la politica de trabajo puesta pueden trabajar;
#    sin ella, IAM les niega todo (no hace falta ningun Deny de horario).
#  - Supervisores: la politica "exigir MFA" se adjunta fuera de horario.
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
# POLITICA DE TRABAJO DE ARTISTA Y LEAD (identica para los dos grupos)
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
# GRUPOS DE OVERTIME: uno por departamento
# La politica de cada grupo apunta SOLO a los recursos de su departamento y
# ademas exige que la etiqueta "departamento" del usuario coincida. Asi, si
# un supervisor suma por error a alguien de otro departamento, esa persona
# queda en el grupo pero no recibe ningun acceso.
# Horario: la Lambda adjunta la politica a las 09:00 y la saca a las 18:00,
# TODOS los dias (incluye sabado y domingo).
# ---------------------------------------------------------------------
resource "aws_iam_group" "overtime" {
  for_each = toset(local.horario_departamentos)
  name     = "vfx-overtime-${each.key}"
}

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
# SUPERVISORES: permiso para sumar y quitar gente de los grupos de overtime
# (manual, cuando hace falta). Siempre adjuntas.
#  - Supervisor de departamento: SOLO el grupo de su propio departamento.
#  - Supervisor VFX general: los siete grupos.
# ---------------------------------------------------------------------
data "aws_iam_policy_document" "supervisor_departamento_overtime" {
  statement {
    sid    = "GestionarOvertimeSoloDeSuDepartamento"
    effect = "Allow"
    actions = [
      "iam:AddUserToGroup",
      "iam:RemoveUserFromGroup",
      "iam:GetGroup",
    ]
    resources = ["arn:aws:iam::*:group/vfx-overtime-$${aws:PrincipalTag/departamento}"]
  }
}

resource "aws_iam_policy" "supervisor_departamento_overtime" {
  name   = "vfx-supervisor-departamento-overtime-policy"
  policy = data.aws_iam_policy_document.supervisor_departamento_overtime.json
}

resource "aws_iam_group_policy_attachment" "supervisor_departamento_overtime_attach" {
  group      = aws_iam_group.supervisor_departamento.name
  policy_arn = aws_iam_policy.supervisor_departamento_overtime.arn
}

data "aws_iam_policy_document" "supervisor_general_overtime" {
  statement {
    sid    = "GestionarOvertimeDeTodosLosDepartamentos"
    effect = "Allow"
    actions = [
      "iam:AddUserToGroup",
      "iam:RemoveUserFromGroup",
      "iam:GetGroup",
    ]
    resources = [for g in aws_iam_group.overtime : g.arn]
  }
}

resource "aws_iam_policy" "supervisor_general_overtime" {
  name   = "vfx-supervisor-general-overtime-policy"
  policy = data.aws_iam_policy_document.supervisor_general_overtime.json
}

resource "aws_iam_group_policy_attachment" "supervisor_general_overtime_attach" {
  group      = aws_iam_group.supervisor_vfx_general.name
  policy_arn = aws_iam_policy.supervisor_general_overtime.arn
}

# ---------------------------------------------------------------------
# LAMBDA vfx-horario: adjunta/saca politicas segun el horario y vacia los
# grupos de overtime los lunes.
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
  horario_grupos_con_politica = concat(
    [
      aws_iam_group.artista.arn,
      aws_iam_group.lead.arn,
      aws_iam_group.supervisor_departamento.arn,
      aws_iam_group.supervisor_vfx_general.arn,
    ],
    [for g in aws_iam_group.overtime : g.arn],
  )

  horario_politicas_permitidas = concat(
    [
      aws_iam_policy.trabajo_artista_lead.arn,
      aws_iam_policy.supervisor_mfa.arn,
    ],
    [for p in aws_iam_policy.overtime_trabajo : p.arn],
  )

  horario_config = {
    semana = {
      trabajo = [
        { grupo = aws_iam_group.artista.name, politica_arn = aws_iam_policy.trabajo_artista_lead.arn },
        { grupo = aws_iam_group.lead.name, politica_arn = aws_iam_policy.trabajo_artista_lead.arn },
      ]
      mfa = [
        { grupo = aws_iam_group.supervisor_departamento.name, politica_arn = aws_iam_policy.supervisor_mfa.arn },
        { grupo = aws_iam_group.supervisor_vfx_general.name, politica_arn = aws_iam_policy.supervisor_mfa.arn },
      ]
    }
    overtime = {
      trabajo = [
        for d in local.horario_departamentos : {
          grupo        = aws_iam_group.overtime[d].name
          politica_arn = aws_iam_policy.overtime_trabajo[d].arn
        }
      ]
    }
    vaciar = [for d in local.horario_departamentos : aws_iam_group.overtime[d].name]
  }
}

data "aws_iam_policy_document" "lambda_horario_permisos" {
  statement {
    sid       = "LeerPoliticasDeLosGruposDeHorario"
    effect    = "Allow"
    actions   = ["iam:ListAttachedGroupPolicies"]
    resources = local.horario_grupos_con_politica
  }

  statement {
    sid       = "AdjuntarYSacarSoloLasPoliticasDeHorario"
    effect    = "Allow"
    actions   = ["iam:AttachGroupPolicy", "iam:DetachGroupPolicy"]
    resources = local.horario_grupos_con_politica

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = local.horario_politicas_permitidas
    }
  }

  statement {
    sid       = "VaciarSoloLosGruposDeOvertime"
    effect    = "Allow"
    actions   = ["iam:GetGroup", "iam:RemoveUserFromGroup"]
    resources = [for g in aws_iam_group.overtime : g.arn]
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


def politicas_adjuntas(iam, grupo):
    arns = set()
    paginador = iam.get_paginator("list_attached_group_policies")
    for pagina in paginador.paginate(GroupName=grupo):
        for politica in pagina["AttachedPolicies"]:
            arns.add(politica["PolicyArn"])
    return arns


def aplicar(iam, par, adjuntar):
    grupo = par["grupo"]
    arn = par["politica_arn"]
    puesta = arn in politicas_adjuntas(iam, grupo)
    if adjuntar and not puesta:
        iam.attach_group_policy(GroupName=grupo, PolicyArn=arn)
        return grupo + ": adjuntada"
    if not adjuntar and puesta:
        iam.detach_group_policy(GroupName=grupo, PolicyArn=arn)
        return grupo + ": sacada"
    return grupo + ": sin cambios"


def vaciar(iam, grupo):
    sacados = []
    paginador = iam.get_paginator("get_group")
    for pagina in paginador.paginate(GroupName=grupo):
        for usuario in pagina["Users"]:
            sacados.append(usuario["UserName"])
    for nombre in sacados:
        iam.remove_user_from_group(GroupName=grupo, UserName=nombre)
    return grupo + ": " + str(len(sacados)) + " usuarios sacados"


def handler(event, context):
    iam = cliente_iam()
    conjunto = event["conjunto"]
    accion = event["accion"]
    resultado = []
    errores = []

    if conjunto == "vaciar":
        tareas = [("vaciar", g) for g in CONFIG["vaciar"]]
    else:
        abrir = accion == "abrir"
        seccion = CONFIG[conjunto]
        tareas = [("trabajo", p, abrir) for p in seccion.get("trabajo", [])]
        tareas += [("mfa", p, not abrir) for p in seccion.get("mfa", [])]

    for tarea in tareas:
        try:
            if tarea[0] == "vaciar":
                resultado.append(vaciar(iam, tarea[1]))
            else:
                resultado.append(aplicar(iam, tarea[1], tarea[2]))
        except Exception as e:
            errores.append(str(tarea[1]) + " -> " + str(e))

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

resource "aws_iam_user_group_membership" "prueba_artista_render_final_membership" {
  user = aws_iam_user.prueba_artista_render_final.name
  groups = [
    aws_iam_group.artista.name,
  ]
}
