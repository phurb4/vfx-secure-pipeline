# =====================================================================
# IP DE ORIGEN PERMITIDA (sesion del 24 de octubre de 2026)
# =====================================================================
# DISENO DE PRODUCCION (la intencion real del proyecto):
#   Todo el equipo del estudio (artista, lead, supervisores) se conecta
#   UNICAMENTE desde la IP publica fija de salida de la VPN de la oficina.
#   Si alguien con credenciales correctas intenta entrar desde otra IP,
#   IAM le niega el acceso igual. Es una capa mas, ademas de usuario,
#   contrasena y MFA de Cognito.
#
# EN ESTE PROYECTO PERSONAL:
#   No hay oficina ni dominio con IP fija, y la IP de casa cambia segun el
#   proveedor de internet. Por eso la IP es una VARIABLE:
#     - El valor real NO se escribe en ningun archivo del repositorio.
#     - Se carga en cada ventana de PowerShell, igual que las claves:
#         $env:TF_VAR_ip_oficina_cidr = "X.X.X.X/32"
#     - Si queda vacia, las politicas solo permiten la red interna de la
#       VPC (10.0.0.0/16), que es el comportamiento anterior.
#
# QUIEN PUEDE CAMBIARLA:
#   Solo el administrador (vfx-admin), porque es quien corre Terraform.
#   Los usuarios del estudio no tienen permiso de escritura sobre el
#   estado remoto ni sobre estos archivos.
#
# GUEST-VIEWER: NO usa esta variable. El invitado no pertenece a la red
#   del estudio; su proteccion es el codigo de un solo uso por email,
#   el permiso de solo lectura y la sesion corta.
#
# DEMO: la laptop sale a internet por el router de casa, asi que AWS ve
#   la IP publica de casa. El tunel OpenVPN entre PC y laptop es local y
#   AWS no lo ve. Antes de grabar, verificar que la IP no haya cambiado.
# =====================================================================

variable "ip_oficina_cidr" {
  description = "IP publica de la oficina en formato CIDR (ej. 190.190.190.190/32). En produccion: IP fija de salida de la VPN. Vacio = solo red interna de la VPC."
  type        = string
  default     = ""

  validation {
    condition     = var.ip_oficina_cidr == "" || can(cidrhost(var.ip_oficina_cidr, 0))
    error_message = "ip_oficina_cidr debe estar vacia o ser un CIDR valido, por ejemplo 190.190.190.190/32."
  }
}

locals {
  rango_vpc_interno = "10.0.0.0/16"

  ips_permitidas = compact([
    local.rango_vpc_interno,
    var.ip_oficina_cidr,
  ])
}