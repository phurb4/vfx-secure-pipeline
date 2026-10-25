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
  default     = "http://localhost.floci.io:4566"
  description = "Direccion de S3 que usa la Lambda. En Floci es la de Floci; en AWS real va vacia."
}