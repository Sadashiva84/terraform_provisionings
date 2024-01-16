# Step 1 - Define your VPC
resource "aws_vpc" "main" {

 cidr_block           = var.vpc_cidr

 enable_dns_hostnames = true

 tags = {

   name = "main"

 }

}

# Step 2 - Add 2 subnets

resource "aws_subnet" "subnet" {

 vpc_id                  = aws_vpc.main.id

 cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, 1)

 map_public_ip_on_launch = true

 availability_zone       = "eu-central-1a"

}



resource "aws_subnet" "subnet2" {

 vpc_id                  = aws_vpc.main.id

 cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, 2)

 map_public_ip_on_launch = true

 availability_zone       = "eu-central-1b"

}

# Step 3 - Create internet gateway (IGW)

resource "aws_internet_gateway" "internet_gateway" {

 vpc_id = aws_vpc.main.id

 tags = {

   Name = "internet_gateway"

 }

}

# Step 4 - Create a Route table and associate the same with subnets

resource "aws_route_table" "route_table" {

 vpc_id = aws_vpc.main.id

 route {

   cidr_block = "0.0.0.0/0"

   gateway_id = aws_internet_gateway.internet_gateway.id

 }

}



resource "aws_route_table_association" "subnet_route" {

 subnet_id      = aws_subnet.subnet.id

 route_table_id = aws_route_table.route_table.id

}



resource "aws_route_table_association" "subnet2_route" {

 subnet_id      = aws_subnet.subnet2.id

 route_table_id = aws_route_table.route_table.id

}

# Step 5 - Create a security group along with ingress and egress rules

resource "aws_security_group" "security_group" {

 name   = "ecs-security-group"

 vpc_id = aws_vpc.main.id



 ingress {

   from_port   = 0

   to_port     = 0

   protocol    = -1

   self        = "false"

   cidr_blocks = ["0.0.0.0/0"]

   description = "any"

 }



 egress {

   from_port   = 0

   to_port     = 0

   protocol    = "-1"

   cidr_blocks = ["0.0.0.0/0"]

 }

}

# Step 6: Create an EC2 launch template

resource "aws_launch_template" "ecs_lt" {

 name_prefix   = "ecs-template"

 image_id      = "ami-062c116e449466e7f"

 instance_type = "t3.micro"



 key_name               = "ec2ecsglog"

 vpc_security_group_ids = [aws_security_group.security_group.id]

 iam_instance_profile {

   name = "ecsInstanceRole"

 }



 block_device_mappings {

   device_name = "/dev/xvda"

   ebs {

     volume_size = 30

     volume_type = "gp2"

   }

 }



 tag_specifications {

   resource_type = "instance"

   tags = {

     Name = "ecs-instance"

   }

 }



 user_data = filebase64("${path.module}/ecs.sh")

}

# Step 7 Create an auto-scaling group (ASG)

resource "aws_autoscaling_group" "ecs_asg" {

 vpc_zone_identifier = [aws_subnet.subnet.id, aws_subnet.subnet2.id]

 desired_capacity    = 2

 max_size            = 3

 min_size            = 1



 launch_template {

   id      = aws_launch_template.ecs_lt.id

   version = "$Latest"

 }



 tag {

   key                 = "AmazonECSManaged"

   value               = true

   propagate_at_launch = true

 }

}

# Step 8 Configure Application Load Balancer (ALB)

resource "aws_lb" "ecs_alb" {

 name               = "ecs-alb"

 internal           = false

 load_balancer_type = "application"

 security_groups    = [aws_security_group.security_group.id]

 subnets            = [aws_subnet.subnet.id, aws_subnet.subnet2.id]



 tags = {

   Name = "ecs-alb"

 }

}



resource "aws_lb_listener" "ecs_alb_listener" {

 load_balancer_arn = aws_lb.ecs_alb.arn

 port              = 80

 protocol          = "HTTP"



 default_action {

   type             = "forward"

   target_group_arn = aws_lb_target_group.ecs_tg.arn

 }

}



resource "aws_lb_target_group" "ecs_tg" {

 name        = "ecs-target-group"

 port        = 80

 protocol    = "HTTP"

 target_type = "ip"

 vpc_id      = aws_vpc.main.id



 health_check {

   path = "/"

 }

}

# Step 9 Provision ECS Cluster

resource "aws_ecs_cluster" "ecs_cluster" {

 name = "my-ecs-cluster"

}

# Step 10 Create capacity providers

resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {

 name = "test1"



 auto_scaling_group_provider {

   auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn



   managed_scaling {

     maximum_scaling_step_size = 1000

     minimum_scaling_step_size = 1

     status                    = "ENABLED"

     target_capacity           = 3

   }

 }

}



resource "aws_ecs_cluster_capacity_providers" "example" {

 cluster_name = aws_ecs_cluster.ecs_cluster.name



 capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]



 default_capacity_provider_strategy {

   base              = 1

   weight            = 100

   capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name

 }

}

# Step 11  Create ECS task definition with Terraform

resource "aws_ecs_task_definition" "ecs_task_definition" {

 family             = "my-ecs-task"

 network_mode       = "awsvpc"

 execution_role_arn = "arn:aws:iam::532199187081:role/ecsTaskExecutionRole"

 cpu                = 256

 runtime_platform {

   operating_system_family = "LINUX"

   cpu_architecture        = "X86_64"

 }

 container_definitions = jsonencode([

   {

     name      = "dockergs"

     image     = "public.ecr.aws/f9n5f1l7/dgs:latest"

     cpu       = 256

     memory    = 512

     essential = true

     portMappings = [

       {

         containerPort = 80

         hostPort      = 80

         protocol      = "tcp"

       }

     ]

   }

 ])

}

# Step 12 Create the ECS service

resource "aws_ecs_service" "ecs_service" {

 name            = "my-ecs-service"

 cluster         = aws_ecs_cluster.ecs_cluster.id

 task_definition = aws_ecs_task_definition.ecs_task_definition.arn

 desired_count   = 2



 network_configuration {

   subnets         = [aws_subnet.subnet.id, aws_subnet.subnet2.id]

   security_groups = [aws_security_group.security_group.id]

 }



 force_new_deployment = true

 placement_constraints {

   type = "distinctInstance"

 }



 triggers = {

   redeployment = timestamp()

 }



 capacity_provider_strategy {

   capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name

   weight            = 100

 }



 load_balancer {

   target_group_arn = aws_lb_target_group.ecs_tg.arn

   container_name   = "dockergs"

   container_port   = 80

 }



 depends_on = [aws_autoscaling_group.ecs_asg]

}

# Step 13 - Run terraform plan and apply commands to provision all the infrastructure defined so far. 



