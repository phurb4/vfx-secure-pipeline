output "vpc_id" {
  description = "ID de la VPC del estudio, leido por otros bloques con terraform_remote_state"
  value       = aws_vpc.vfx_vpc.id
}