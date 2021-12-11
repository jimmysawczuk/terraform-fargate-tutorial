locals {
  repository_url = "ghcr.io/jimmysawczuk/sun-api"
}

# We need a cluster in which to put our service.
resource "aws_ecs_cluster" "app" {
  name = "app"
}

# An ECR repository is a private alternative to Docker Hub.
resource "aws_ecr_repository" "sun_api" {
  name = "sun-api"
}

# Log groups hold logs from our app.
resource "aws_cloudwatch_log_group" "sun_api" {
  name = "/ecs/sun-api"
}

# The main service.
resource "aws_ecs_service" "sun_api" {
  name            = "sun-api"
  task_definition = aws_ecs_task_definition.sun_api.arn
  cluster         = aws_ecs_cluster.app.id
  launch_type     = "FARGATE"

  desired_count = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.sun_api.arn
    container_name   = "sun-api"
    container_port   = "3000"
  }

  network_configuration {
    assign_public_ip = false

    security_groups = [
      aws_security_group.egress_all.id,
      aws_security_group.ingress_api.id,
    ]

    subnets = [
      aws_subnet.private_d.id,
      aws_subnet.private_e.id,
    ]
  }
}

# The task definition for our app.
resource "aws_ecs_task_definition" "sun_api" {
  family = "sun-api"

  container_definitions = <<EOF
  [
    {
      "name": "sun-api",
      "image": "${local.repository_url == "" ? aws_ecr_repository.sun_api.repository_url : local.repository_url}:latest",
      "portMappings": [
        {
          "containerPort": 3000
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "us-east-1",
          "awslogs-group": "/ecs/sun-api",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]

EOF

  execution_role_arn = aws_iam_role.sun_api_task_execution_role.arn

  # These are the minimum values for Fargate containers.
  cpu                      = 256
  memory                   = 512
  requires_compatibilities = ["FARGATE"]

  # This is required for Fargate containers (more on this later).
  network_mode = "awsvpc"
}

# This is the role under which ECS will execute our task. This role becomes more important
# as we add integrations with other AWS services later on.

# The assume_role_policy field works with the following aws_iam_policy_document to allow
# ECS tasks to assume this role we're creating.
resource "aws_iam_role" "sun_api_task_execution_role" {
  name               = "sun-api-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Normally we'd prefer not to hardcode an ARN in our Terraform, but since this is an AWS-managed
# policy, it's okay.
data "aws_iam_policy" "ecs_task_execution_role" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach the above policy to the execution role.
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.sun_api_task_execution_role.name
  policy_arn = data.aws_iam_policy.ecs_task_execution_role.arn
}

resource "aws_lb_target_group" "sun_api" {
  name        = "sun-api"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.app_vpc.id

  health_check {
    enabled = true
    path    = "/health"
  }

  depends_on = [aws_alb.sun_api]
}

resource "aws_alb" "sun_api" {
  name               = "sun-api-lb"
  internal           = false
  load_balancer_type = "application"

  subnets = [
    aws_subnet.public_d.id,
    aws_subnet.public_e.id,
  ]

  security_groups = [
    aws_security_group.http.id,
    aws_security_group.https.id,
    aws_security_group.egress_all.id,
  ]

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_alb_listener" "sun_api_http" {
  load_balancer_arn = aws_alb.sun_api.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "sun_api_https" {
  load_balancer_arn = aws_alb.sun_api.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.sun_api.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sun_api.arn
  }
}

output "alb_url" {
  value = "http://${aws_alb.sun_api.dns_name}"
}

resource "aws_acm_certificate" "sun_api" {
  domain_name       = "sun-api.jimmysawczuk.net"
  validation_method = "DNS"
}

output "domain_validations" {
  value = aws_acm_certificate.sun_api.domain_validation_options
}
