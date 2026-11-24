terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "app" {
  name   = "orders-api"
  vpc_id = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name   = "orders-db"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

resource "aws_db_instance" "orders" {
  identifier                  = "orders-db"
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = "db.t3.medium"
  allocated_storage           = 20
  db_name                     = "orders"
  username                    = "orders_app"
  manage_master_user_password = true
  vpc_security_group_ids      = [aws_security_group.db.id]
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "orders-db-final"
}

resource "aws_ecs_cluster" "main" {
  name = "orders"
}

resource "aws_ecs_task_definition" "api" {
  family                   = "orders-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"

  container_definitions = jsonencode([{
    name         = "api"
    image        = "ghcr.io/example/orders-api:1.4.0"
    portMappings = [{ containerPort = 8080 }]
    environment = [
      { name = "DB_HOST", value = aws_db_instance.orders.address },
      { name = "DB_POOL_SIZE", value = "40" }
    ]
  }])
}

resource "aws_ecs_service" "api" {
  name            = "orders-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 4
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }
}
