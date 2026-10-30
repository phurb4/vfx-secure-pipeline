provider "aws" {
  region = "us-east-2"
}

variable "ami_id" {
  description = "AMI de las instancias de render. Vacio = usa la ultima Amazon Linux 2023 (provisoria, hasta tener una AMI propia con el software de render)."
  type        = string
  default     = ""
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
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
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023.id
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

  # DISENO: Spot Instances (hasta ~90% mas baratas que On-Demand).
  # CUENTA REAL: la SCP de la Organizacion niega ec2:RunInstances con Spot
  # (verificado con --dry-run el 30 de octubre de 2026), asi que aca van
  # instancias On-Demand. En una cuenta sin esa restriccion se vuelve a agregar:
  #   instance_market_options { market_type = "spot" }

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
}

# Politica de bajada: deja el grupo en 0 instancias
resource "aws_autoscaling_policy" "render_scale_in" {
  name                   = "render-scale-in"
  autoscaling_group_name = aws_autoscaling_group.render_farm_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ExactCapacity"
  scaling_adjustment     = 0
  cooldown               = 300
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