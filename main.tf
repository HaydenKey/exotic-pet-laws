# Boiler Plate Code
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = "us-east-1"
  access_key = var.AWS_ACCESS_KEY_ID
  secret_key = var.AWS_SECRET_ACCESS_KEY
}


# Create vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = {
    Name = "production"
  }
}


# Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}


# Create Custom Route Table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}


# Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet"
  }
}


# Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}


# Create Security Group to allow port 22,80,443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}


# Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}


# Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_instance.web-server-instance]
}

# Prints out the public IP address for convenience
output "server_public_ip" {
  value = aws_eip.one.public_ip
}

# create lambda
resource "aws_lambda_function" "get_state_function" {
  filename      = "./lambda/get_state_lambda.zip"
  function_name = "lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
}

# Create IAM role for lambda
resource "aws_iam_role" "lambda_role" {
  name               = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Define API Gateway REST API
resource "aws_api_gateway_rest_api" "get_state_api" {
  name        = "get-state-api"
  description = "An API that gets the legal information about what exotic pets can be owned in a given state"
}

# Define API Gateway resource and method
resource "aws_api_gateway_resource" "get_state_resource" {
  rest_api_id = aws_api_gateway_rest_api.get_state_api.id
  parent_id   = aws_api_gateway_rest_api.get_state_api.root_resource_id
  path_part   = "state"
}

# Associate integration with method
resource "aws_api_gateway_method" "get_state_method" {
  rest_api_id   = aws_api_gateway_rest_api.get_state_api.id
  resource_id   = aws_api_gateway_resource.get_state_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Define Lambda integration with API Gateway
resource "aws_api_gateway_integration" "get_state_integration" {
  rest_api_id             = aws_api_gateway_rest_api.get_state_api.id
  resource_id             = aws_api_gateway_resource.get_state_resource.id
  http_method             = aws_api_gateway_method.get_state_method.http_method
  integration_http_method = "POST"  # Adjust this if your Lambda function expects a different HTTP method
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_state_function.invoke_arn
}

#data "aws_iam_policy_document" "s3_put_object_policy" {
#  statement {
#    actions   = ["s3:PutObject"]
#    resources = ["arn:aws:s3:::your_bucket_name/*"]  # Replace your_bucket_name with the actual bucket name
#  }
#}
#
#resource "aws_s3_bucket" "exotic_pets_html_bucket" {
#  bucket = "exotic_pets_html_bucket"
#
#  tags = {
#    Name = "Exotic Pets HTML Bucket"
#  }
#}
#
#resource "aws_s3_bucket_object" "exotic_pets_html_object" {
#  bucket = "exotic_pets_html_bucket"
#  key    = "new_object_key"
#  source = "./data/index.html"
#
#  # The filemd5() function is available in Terraform 0.11.12 and later
#  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
#  # etag = "${md5(file("path/to/file"))}"
#  etag = filemd5("./data/index.html")
#}


# Define API Gateway deployment
resource "aws_api_gateway_deployment" "get_state_prod_deployment" {
  depends_on = [
    aws_api_gateway_method.get_state_method,
    aws_api_gateway_integration.get_state_integration,
    aws_api_gateway_resource.get_state_resource,
    aws_api_gateway_rest_api.get_state_api
  ]

  rest_api_id = aws_api_gateway_rest_api.get_state_api.id
  stage_name  = "prod"
}



# Create Ubuntu server and install/enable apache2
resource "aws_instance" "web-server-instance" {
  ami               = "ami-085925f297f89fce1"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "main-key"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo bash -c 'echo Hello World! > /var/www/html/index.html'
                sudo systemctl start apache2
EOF
  tags      = {
    Name = "web-server"
  }
}

# These push the index.html file to the server, but it just serves the default page for some reason
# sudo aws s3 cp s3://exotic-pets-html-bucket/index.html /var/www/html/index.html

