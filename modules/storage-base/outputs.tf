output "output_bucket" {
  value       = aws_s3_bucket.output.id
  description = "Nombre del bucket de Output de este departamento."
}

output "input_bucket" {
  value       = aws_s3_bucket.input.id
  description = "Nombre del bucket de Input de este departamento."
}