import os
# B404: Bandit advierte por el solo hecho de importar subprocess, porque es
# la via clasica de inyeccion de comandos del SO. Aceptado: es la unica forma
# de invocar el binario de FFmpeg desde la Lambda. El uso real se blinda abajo
# (ver linea del subprocess.run, sin shell=True).
import subprocess  # nosec B404
import urllib.parse
import boto3

s3 = boto3.client("s3", endpoint_url=os.environ.get("S3_ENDPOINT_URL") or None)


def encontrar_ffmpeg():
    for ruta in ["/opt/bin/ffmpeg", "/var/task/__layers__/bin/ffmpeg", "/var/task/bin/ffmpeg"]:
        if os.path.exists(ruta):
            return ruta
    raise FileNotFoundError("No se encontro el binario de ffmpeg en las rutas conocidas")

FFMPEG = encontrar_ffmpeg()

def encontrar_font():
    for ruta in ["/opt/fonts/arial.ttf", "/var/task/__layers__/fonts/arial.ttf", "/var/task/fonts/arial.ttf"]:
        if os.path.exists(ruta):
            return ruta
    raise FileNotFoundError("No se encontro la fuente arial.ttf en las rutas conocidas")

FONT = encontrar_font()


DAILIES_BUCKET = os.environ["DAILIES_BUCKET"]
DEPT_PREFIX = os.environ["DEPT_PREFIX"]


def escape_drawtext(valor):
    valor = valor.replace("\\", "\\\\")
    valor = valor.replace(":", "\\:")
    valor = valor.replace("'", "\\'")
    return valor


def lambda_handler(event, context):
    record = event["Records"][0]
    src_bucket = record["s3"]["bucket"]["name"]
    src_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

    nombre_archivo = os.path.basename(src_key)
    nombre_sin_ext = os.path.splitext(nombre_archivo)[0]

    # B108: /tmp hardcodeado. Aceptado como falso positivo en el contexto de Lambda:
    # /tmp es el UNICO almacenamiento escribible del entorno de ejecucion, es efimero
    # y esta aislado por invocacion (no es un /tmp compartido entre procesos como en un
    # servidor tradicional), por lo que el riesgo que describe CWE-377 no aplica aqui.
    local_in = f"/tmp/{nombre_archivo}"   # nosec B108
    local_out = f"/tmp/quemado_{nombre_archivo}"  # nosec B108

    s3.download_file(src_bucket, src_key, local_in)

    nombre_seguro = "".join(c if (c.isascii() and c.isalnum()) or c in "_-." else "_" for c in nombre_sin_ext)
    shot = escape_drawtext(nombre_seguro)
    font = FONT

    estilo = f"fontfile='{font}':fontcolor=white:fontsize=28:box=1:boxcolor=black@0.7:boxborderw=10"

    vf = (
        f"drawtext={estilo}:text='{shot}':x=50:y=50, "
        f"drawtext={estilo}:text='codec\\: H264 | 24 FPS':x=50:y=100, "
        f"drawtext={estilo}:timecode='00\\:00\\:00\\:00':timecode_rate=24:x=(w-text_w-50):y=50, "
        f"drawtext={estilo}:text='%{{eif\\:n\\:d\\:5}}':x=(w-text_w-50):y=100"
    )

    cmd = [
        FFMPEG, "-y",
        "-i", local_in,
        "-vf", vf,
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        local_out,
    ]

    # B603: subprocess sin shell=True. Es justamente la forma SEGURA de invocarlo:
    # 'cmd' es una LISTA de argumentos, no una cadena interpretada por el shell, lo
    # que evita la inyeccion de comandos. Ademas el nombre del shot que viene del
    # evento S3 ya se escapa antes de llegar aca. Aceptado.
    resultado = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)  # nosec B603
    if resultado.returncode != 0:
        error_ffmpeg = resultado.stderr.decode()
        print(error_ffmpeg)
        raise Exception(f"FFmpeg fallo: {error_ffmpeg[-1500:]}")

    dst_key = f"{DEPT_PREFIX}/{nombre_archivo}"
    s3.upload_file(local_out, DAILIES_BUCKET, dst_key)

    return {
        "statusCode": 200,
        "mensaje": f"Quemado OK: {src_key} -> {DAILIES_BUCKET}/{dst_key}",
    }