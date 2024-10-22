provider "aws" {
  region = "us-east-1"
}
# Obtener información de la VPC por defecto
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "rds_sg" {
  name        = "allow_vpc_access"
  description = "Allow MySQL traffic within the VPC"

  # Permitir acceso dentro de la VPC
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]  # Limitar acceso VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

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
  publicly_accessible  = false  # Mantener la instancia privada
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
}

# Subnets para RDS en la VPC
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = data.aws_subnets.default.ids
  description = "RDS subnet group"
}

# Obtener todas las subnets de la VPC por defecto
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# LAMBDA
# Crear rol IAM para la función Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

# Asignar políticas al rol de la función Lambda
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec_role.name
}

# Crear la función Lambda
resource "aws_lambda_function" "franchise_function" {
  function_name = "franchiseFunction"
  handler       = "com.example.franchiseapi.Application::handleRequest" 
  runtime       = "java17"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 512
  filename      = "lambda_example/lambda.zip" 
}

# Crear API Gateway
resource "aws_api_gateway_rest_api" "franchise_api" {
  name        = "FranchiseAPI"
  description = "API para gestionar franquicias, sucursales y productos"
}

# Definir recursos para cada operación
resource "aws_api_gateway_resource" "franchise" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  parent_id   = aws_api_gateway_rest_api.franchise_api.root_resource_id
  path_part   = "franchise"
}

resource "aws_api_gateway_resource" "branch" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  parent_id   = aws_api_gateway_resource.franchise.id
  path_part   = "branch"
}

resource "aws_api_gateway_resource" "product" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  parent_id   = aws_api_gateway_resource.branch.id
  path_part   = "product"
}

# Exponer métodos POST para agregar franquicia
resource "aws_api_gateway_method" "post_franchise" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.franchise.id
  http_method   = "POST"
  authorization = "NONE"
}

# Exponer métodos POST para agregar sucursal a una franquicia
resource "aws_api_gateway_method" "post_branch" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.branch.id
  http_method   = "POST"
  authorization = "NONE"
}

# Exponer métodos POST para agregar producto a una sucursal
resource "aws_api_gateway_method" "post_product" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.product.id
  http_method   = "POST"
  authorization = "NONE"
}

# Exponer métodos DELETE para eliminar un producto
resource "aws_api_gateway_method" "delete_product" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.product.id
  http_method   = "DELETE"
  authorization = "NONE"
}

# Exponer métodos PUT para modificar el stock de un producto
resource "aws_api_gateway_resource" "product_stock" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  parent_id   = aws_api_gateway_resource.product.id
  path_part   = "stock"
}

resource "aws_api_gateway_method" "put_product_stock" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.product_stock.id
  http_method   = "PUT"
  authorization = "NONE"
}

# Integrar los métodos con la función Lambda
resource "aws_api_gateway_integration" "lambda_post_franchise" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.franchise.id
  http_method = aws_api_gateway_method.post_franchise.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_post_branch" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.branch.id
  http_method = aws_api_gateway_method.post_branch.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_post_product" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.product.id
  http_method = aws_api_gateway_method.post_product.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_delete_product" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.product.id
  http_method = aws_api_gateway_method.delete_product.http_method
  type        = "AWS_PROXY"
  integration_http_method = "DELETE"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_put_product_stock" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.product_stock.id
  http_method = aws_api_gateway_method.put_product_stock.http_method
  type        = "AWS_PROXY"
  integration_http_method = "PUT"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

# Exponer métodos PUT para actualizar el nombre de una franquicia
resource "aws_api_gateway_method" "put_franchise_name" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.franchise.id
  http_method   = "PUT"
  authorization = "NONE"
}

# Exponer métodos PUT para actualizar el nombre de una sucursal
resource "aws_api_gateway_method" "put_branch_name" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.branch.id
  http_method   = "PUT"
  authorization = "NONE"
}

# Exponer métodos PUT para actualizar el nombre de un producto
resource "aws_api_gateway_method" "put_product_name" {
  rest_api_id   = aws_api_gateway_rest_api.franchise_api.id
  resource_id   = aws_api_gateway_resource.product.id
  http_method   = "PUT"
  authorization = "NONE"
}

# Integrar los métodos PUT con la función Lambda
resource "aws_api_gateway_integration" "lambda_put_franchise_name" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.franchise.id
  http_method = aws_api_gateway_method.put_franchise_name.http_method
  type        = "AWS_PROXY"
  integration_http_method = "PUT"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_put_branch_name" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.branch.id
  http_method = aws_api_gateway_method.put_branch_name.http_method
  type        = "AWS_PROXY"
  integration_http_method = "PUT"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

resource "aws_api_gateway_integration" "lambda_put_product_name" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  resource_id = aws_api_gateway_resource.product.id
  http_method = aws_api_gateway_method.put_product_name.http_method
  type        = "AWS_PROXY"
  integration_http_method = "PUT"
  uri = aws_lambda_function.franchise_function.invoke_arn
}

# Desplegar el API Gateway
resource "aws_api_gateway_deployment" "franchise_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.franchise_api.id
  stage_name  = "dev"

  depends_on = [
    aws_api_gateway_method.post_franchise,
    aws_api_gateway_method.post_branch,
    aws_api_gateway_method.post_product,
    aws_api_gateway_method.delete_product,
    aws_api_gateway_method.put_product_stock,
    aws_api_gateway_method.put_franchise_name,
    aws_api_gateway_method.put_branch_name,
    aws_api_gateway_method.put_product_name,
    aws_api_gateway_integration.lambda_post_franchise,
    aws_api_gateway_integration.lambda_post_branch,
    aws_api_gateway_integration.lambda_post_product,
    aws_api_gateway_integration.lambda_delete_product,
    aws_api_gateway_integration.lambda_put_product_stock,
    aws_api_gateway_integration.lambda_put_franchise_name,
    aws_api_gateway_integration.lambda_put_branch_name,
    aws_api_gateway_integration.lambda_put_product_name
  ]
}