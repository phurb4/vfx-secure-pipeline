import os
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
DEPT_PREFIX = os.environ.get("DEPT_PREFIX", "MOD")
DEPARTMENT_NAME = os.environ.get("DEPARTMENT_NAME", "modelado")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    shot = event["shot"]
    uploaded_by = event.get("uploaded_by", "desconocido")
    asset_id = f"{DEPT_PREFIX}_{shot}"

    # Busca la version mas alta que ya existe para este asset
    response = table.query(
        KeyConditionExpression=Key("asset_id").eq(asset_id),
        ScanIndexForward=False,
        Limit=1,
    )
    items = response.get("Items", [])

    if items:
        last_number = int(items[0]["version"].lstrip("v"))
    else:
        last_number = 0

    new_version = f"v{last_number + 1:03d}"
    file_name = f"{asset_id}_{new_version}"

    # Crea la ficha de la nueva version. Si ya existe, falla en vez de pisarla.
    table.put_item(
        Item={
            "asset_id": asset_id,
            "version": new_version,
            "file_name": file_name,
            "department": DEPARTMENT_NAME,
            "uploaded_by": uploaded_by,
            "uploaded_at": datetime.now(timezone.utc).isoformat(),
            "approval_status": "pendiente_revision",
        },
        ConditionExpression="attribute_not_exists(asset_id)",
    )

    return {
        "asset_id": asset_id,
        "version": new_version,
        "file_name": file_name,
    }