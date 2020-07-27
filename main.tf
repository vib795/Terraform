#################################################################################################
# terraform init                                                                                #
# terraform plan                                                                                #
# terraform apply                                                                               #
# terraform destroy                                                                             #
# terraform state <sub command>                                                                 #
# terraform destroy -target <provider>.<resource_type> ---> to only destroy certain resources   #
# terraform apply -target <provider>.<resource_type> ---> to only apply certain resources       #
# terraform apply -var "<var_name> = value" ---> to assign values to variables on the fly       #
#                                                                                               #
#                                                                                               #
# Also, to assign values to vars we can create a file terraform.tfvars which terraform looks for#
# by default and move all the variable assignments in the file.                                 #
# To send var values from a custome filename:                                                   #
# terraform apply -var-file filename                                                            #
#################################################################################################

# Configure the AWS Provider
provider "aws" {
  region  = "us-east-2" #hard coded region for a datacenter
  access_key = "" # value from the key file that you generate from the Key pairs option
  secret_key = "" # value from the key file that you generate from the Key pairs option
}

# resource "<provider>_<resource_type>" "name"{
  # config options.....
  # key1 = value1
  # key2 = value2 

# }
############################################
/* resource "aws_instance" "my-first-server" {
  ami           = "ami-0a63f96e85105c6d3"
  instance_type = "t2.micro"

  tags = {
    Name = "Terraform_Ubuntu"
  }
}

resource "aws_vpc" "myFirstVPC" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "Terraform_VPC"
  }
}

resource "aws_subnet" "myFristSubnet" {
  vpc_id     = aws_vpc.myFirstVPC.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "Terraform_Subnet"
  }
} */
############################################

# 1. Create VPC.
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "production"
  }
}

# 2. Create Internet Gateway (assign a public IP).
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

# 3. Create a custome Route Table.
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0" # instead of routing -> "10.0.1.0/24" to the internet i sent all traffic to the internet using 0.0.0.0/0 
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

#######################################################
# How to use variables                                #
#######################################################
variable "subnet_prefix" { # all the parameters below are optional and can be left blank or not written at all
  description = "cidr block for the subnet"
  #default = ""
  #type = ""
}

# 4. Create a subnet. 
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  #cidr_block = "10.0.1.0/24"
  cidr_block = var.subnet_prefix
  availability_zone = "us-east-2a"

  tags = {
    Name = "prod-subnet"
  }
}

# 5. Associate subnet with route table.
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# 6. Create security group to allow port 22,80 and 443.
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web traffic"
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

# 7. Create a network interface with an ip in the subnet that was created in step 4.
resource "aws_network_interface" "web-server-vib" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"] # this comes from the above subnet of 10.0.1.0/24
  security_groups = [aws_security_group.allow_web.id]
}

# 8. Assign an elastic IP to the network interface created in step 7.
resource "aws_eip" "one" {
  vpc                       = true # because our EIP is within a VPC
  network_interface         = aws_network_interface.web-server-vib.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw] # because we cannot have an EIP unless we have a gateway setup
}

# 9. Create an Ubuntu server and install/enable apache2.
resource "aws_instance" "web-server-instance" {
  ami = "ami-0a63f96e85105c6d3"
  instance_type = "t2.micro"
  availability_zone = "us-east-2a"
  key_name = "main-key-terraform"

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-vib.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo -i apt update -y
              sudo -i apt install apache2 -y
              sudo -i systemctl start apache2
              sudo -i bash -c 'echo your very first web server > /var/www/html/index.html'
              EOF

  tags = {
    Name = "web-server"
  }
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}