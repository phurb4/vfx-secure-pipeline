variable "aws_access_key" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2         = "http://localhost:4566"
    autoscaling = "http://localhost:4566"
    sqs         = "http://localhost:4566"
    cloudwatch  = "http://localhost:4566"
  }
}

variable "ami_id" {
  description = "AMI de las instancias de render. En Floci es un ID de prueba; en AWS real hay que poner una AMI valida."
  type        = string
  default     = "ami-0abcdef1234567890"
}

variable "instance_type" {
  description = "Tipo de instancia. t3.micro para pruebas; un render real usaria una familia de computo como c5."
  type        = string
  default     = "t3.micro"
}

# Busca la VPC que ya creaste en 01-Network
data "aws_vpc" "vfx_vpc" {
  tags = {
    Name = "vfx-vpc"
  }
}

# Busca la cola que ya creaste en 05-SQS
data "aws_sqs_queue" "render_queue" {
  name = "render-queue"
}

# Subnet propia del departamento Render Final
resource "aws_subnet" "render_final_subnet" {
  vpc_id     = data.aws_vpc.vfx_vpc.id
  cidr_block = "10.0.7.0/24"

  tags = {
    Name         = "render-final-subnet"
    departamento = "render-final"
    proyecto     = "pipeline-vfx"
  }
}

# Busca el Security Group que ya existe en 01-Network (no se vuelve a crear aca)
data "aws_security_group" "render_farm_sg" {
  filter {
    name   = "group-name"
    values = ["render-farm-sg"]
  }
}

# Launch template: la "receta" de cada instancia de render
resource "aws_launch_template" "render_lt" {
  name          = "render-farm-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [data.aws_security_group.render_farm_sg.id]

  # Disco EBS efimero: se destruye junto con la instancia
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Spot Instances: hasta ~90% mas baratas que On-Demand
  instance_market_options {
    market_type = "spot"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name         = "render-farm"
      departamento = "render-final"
      ambiente     = "desarrollo"
      proyecto     = "pipeline-vfx"
    }
  }

  tags = {
    departamento = "render-final"
    ambiente     = "desarrollo"
    proyecto     = "pipeline-vfx"
  }
}

# Auto Scaling Group: arranca en 0 instancias (cero costo en reposo)
resource "aws_autoscaling_group" "render_farm_asg" {
  name                = "render-farm-asg"
  min_size            = 0
  max_size            = 3
  desired_capacity    = 0
  vpc_zone_identifier = [aws_subnet.render_final_subnet.id]

  launch_template {
    id      = aws_launch_template.render_lt.id
    version = aws_launch_template.render_lt.latest_version
  }

  tag {
    key                 = "Name"
    value               = "render-farm"
    propagate_at_launch = true
  }

  tag {
    key                 = "departamento"
    value               = "render-final"
    propagate_at_launch = true
  }

  tag {
    key                 = "proyecto"
    value               = "pipeline-vfx"
    propagate_at_launch = true
  }

  # La capacidad deseada la va a mover el escalado (o nosotros a mano en las pruebas);
  # Terraform no debe volver a ponerla en 0 en cada apply.
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# --- Escalado segun la cola de SQS ---

# Politica de subida: suma 1 instancia
resource "aws_autoscaling_policy" "render_scale_out" {
  name                   = "render-scale-out"
  autoscaling_group_name = aws_autoscaling_group.render_farm_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300

  # SOLO EMULADOR: Floci devuelve enabled=false al leer la politica, lo que genera
  # un cambio fantasma en cada plan. Quitar este bloque al desplegar en AWS real.
  lifecycle {
    ignore_changes = [enabled]
  }
}

# Politica de bajada: deja el grupo en 0 instancias
resource "aws_autoscaling_policy" "render_scale_in" {
  name                   = "render-scale-in"
  autoscaling_group_name = aws_autoscaling_group.render_farm_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ExactCapacity"
  scaling_adjustment     = 0
  cooldown               = 300

  # SOLO EMULADOR: ver comentario de render_scale_out.
  lifecycle {
    ignore_changes = [enabled]
  }
}

# Alarma: hay trabajos esperando en la cola -> subir
resource "aws_cloudwatch_metric_alarm" "render_queue_has_jobs" {
  alarm_name          = "render-queue-has-jobs"
  alarm_description   = "Hay shots esperando render en la cola"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    QueueName = data.aws_sqs_queue.render_queue.name
  }

  alarm_actions = [aws_autoscaling_policy.render_scale_out.arn]
}

# Alarma: la cola esta vacia hace 5 minutos -> bajar a 0
resource "aws_cloudwatch_metric_alarm" "render_queue_empty" {
  alarm_name          = "render-queue-empty"
  alarm_description   = "La cola de render lleva 5 minutos vacia"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 0
  comparison_operator = "LessThanOrEqualToThreshold"

  dimensions = {
    QueueName = data.aws_sqs_queue.render_queue.name
  }

  alarm_actions = [aws_autoscaling_policy.render_scale_in.arn]
}