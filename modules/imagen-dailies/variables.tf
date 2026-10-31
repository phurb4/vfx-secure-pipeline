variable "departamento" {
  type        = string
  description = "Nombre del departamento, en minuscula. Arma los nombres de la Lambda, el rol y los buckets."
}

variable "dailies_bucket" {
  type        = string
  description = "Nombre del bucket unico de Dailies donde la Lambda copia el PNG."
}
variable "s3_endpoint" {
  type        = string
  default     = ""
  description = "Direccion de S3 que usa la Lambda. Vacia en AWS real (usa el endpoint normal); en Floci era http://localhost.floci.io:4566."
}