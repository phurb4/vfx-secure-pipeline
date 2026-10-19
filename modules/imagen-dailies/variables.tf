variable "departamento" {
  type        = string
  description = "Nombre del departamento, en minuscula. Arma los nombres de la Lambda, el rol y los buckets."
}

variable "dailies_bucket" {
  type        = string
  description = "Nombre del bucket unico de Dailies donde la Lambda copia el PNG."
}