variable "departamento" {
  type        = string
  description = "Nombre del departamento, en minuscula. Arma los nombres de la Lambda, el rol y los buckets."
}

variable "dailies_bucket" {
  type        = string
  description = "Nombre del bucket unico de Dailies donde la Lambda escribe el MP4 quemado."
}

variable "ffmpeg_layer_arn" {
  type        = string
  description = "ARN de la capa de FFmpeg ya publicada, compartida por todos los departamentos."
}