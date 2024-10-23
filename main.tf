provider "aws" {
  region = "us-east-1"
}

# Obtener información de la VPC por defecto
data "aws_vpc" "default" {
  default = true
}

# Obtener todas las subnets de la VPC por defecto
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Grupo de seguridad para la instancia de RDS
resource "aws_security_group" "rds_sg" {
  name        = "allow_all_access"
  description = "Allow MySQL traffic from anywhere"

  # Permitir acceso desde cualquier IP
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Permitir acceso desde cualquier IP
  }

  # Permitir tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Subnets para RDS en la VPC
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = data.aws_subnets.default.ids
  description = "RDS subnet group"
}

# Instancia de base de datos RDS
resource "aws_db_instance" "franchise_db" {
  allocated_storage    = 20
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"  
  db_name             = "franchise_db"
  username            = var.db_username  
  password            = var.db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  publicly_accessible  = true  
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
}

# Rol de ejecución para ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

# Políticas para el rol de ejecución
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# Repositorio ECR para la imagen de Docker
resource "aws_ecr_repository" "franchise_api" {
  name = "franchise-api"
}

# Cluster ECS
resource "aws_ecs_cluster" "franchise_cluster" {
  name = "franchise-cluster"
}

# Grupo de seguridad para el servicio ECS
resource "aws_security_group" "ecs_sg" {
  name        = "ecs_sg"
  description = "Allow traffic for ECS service"

  # Permitir acceso al puerto de la aplicación (por ejemplo, 8081)
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Permitir acceso desde cualquier IP
  }

  # Permitir tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Definición de la tarea ECS
resource "aws_ecs_task_definition" "franchise_task" {
  family                   = "franchise-task"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = "256"  # Ajusta según tus necesidades
  memory                  = "512"  # Ajusta según tus necesidades
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn  # Agregar el rol de ejecución

  container_definitions = jsonencode([{
    name      = "franchise-api"
    image     = "${aws_ecr_repository.franchise_api.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 8081  # Ajustado al puerto definido en .env
      hostPort      = 8081
      protocol      = "tcp"
    }]
    
    # Definir variables de entorno aquí
    environment = [
      {
        name  = "SPRING_DATASOURCE_URL"
        value = "jdbc:mysql://${aws_db_instance.franchise_db.address}:3306/franchise_db"
      },
      {
        name  = "SPRING_DATASOURCE_USERNAME"
        value = var.db_username  # Valor del usuario
      },
      {
        name  = "SPRING_DATASOURCE_PASSWORD"
        value = var.db_password  # Valor de la contraseña
      },
      {
        name  = "SPRING_SERVER_PORT"
        value = "8081"  # Puerto del servidor
      }
    ]
  }])
}

# Servicio ECS
resource "aws_ecs_service" "franchise_service" {
  name            = "franchise-service"
  cluster         = aws_ecs_cluster.franchise_cluster.id
  task_definition = aws_ecs_task_definition.franchise_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]  # Usar el grupo de seguridad para ECS
    assign_public_ip = true  # Asegurarte de que se asigne una IP pública
  }
}

output "repository_url" {
  value = aws_ecr_repository.franchise_api.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.franchise_cluster.name
}
