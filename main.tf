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
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"  
  db_name              = "franchise_db"
  username             = var.db_username  
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  publicly_accessible  = true  
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
}
