# connect to instance's public IP with this:
# nmap -sV -Pn -p T:25565 <instance_public_ip>

# basic requriements
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~>5.0"
    }
  }
}

# select whatever region is closest to you
provider "aws" {
    profile = "default"
    region = "us-west-2"
}

# make sure we have the correct data source
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  owners = ["099720109477"]
}

# auto discover default VPC if var.vpc_id is empty
data "aws_vpc" "default" {
  default = true
}
locals {
  chosen_vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default.id
}

# security group
resource "aws_security_group" "minecraft_secgroup" {
  name = "minecraft-server-security-group"
  vpc_id = local.chosen_vpc_id
  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Minecraft"
    from_port = 25565
    to_port = 25565
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# import public key
resource "aws_key_pair" "minecraft" {
  key_name   = "minecraft-key"
  public_key = file(var.public_key_path)
}

# ec2 instance setup (this is a long one)
resource "aws_instance" "minecraft"{
    ami = data.aws_ami.ubuntu.id
    instance_type = "t2.medium"
    key_name = aws_key_pair.minecraft.key_name
    vpc_security_group_ids = [aws_security_group.minecraft_secgroup.id]
    
    root_block_device {
      volume_size = 16
      volume_type = "gp3"
    }

    user_data = <<-EOF
                #!/usr/bin/env bash
                # update & install Java
                apt-get update -y && apt-get upgrade -y
                apt-get install -y openjdk-21-jdk wget

                # prepare Minecraft directory
                mkdir -p /home/ubuntu/minecraft
                cd /home/ubuntu/minecraft

                # download latest server jar
                wget java -Xmx1024M -Xms1024M -jar minecraft_server.1.21.5.jar nogui -O minecraft_server.jar

                # accept EULA
                echo "eula=true" > eula.txt

                # create systemd service
                cat << SERVICE > /etc/systemd/system/minecraft.service
                [Unit]
                Description=Minecraft Java Server
                After=network.target

                [Service]
                WorkingDirectory=/home/ubuntu/minecraft
                ExecStart=/usr/bin/java -Xms1024M -Xmx1024M -jar /home/ubuntu/minecraft/minecraft_server.jar nogui
                ExecStop=/bin/kill -SIGINT \$MAINPID
                Restart=on-failure
                RestartSec=20
                SuccessExitStatus=0 1

                [Install]
                WantedBy=multi-user.target
                SERVICE

                # enable & start
                systemctl daemon-reload
                systemctl enable minecraft
                systemctl start minecraft
                EOF

    tags = {
      Name = "Minecraft Server with Terraform"
    }
}

# elastic IP
resource "aws_eip" "minecraft_ip" {
  instance = aws_instance.minecraft.id
  domain = "vpc"
  depends_on = [aws_instance.minecraft]
}

# outputs
output "minecraft_server_public_ip" {
  description = "Public IP for the Minecraft server"
  value = aws_eip.minecraft_ip.public_ip
}
output "ssh_command" {
  description = "how to SSH into server"
  value = "ssh -i ${var.public_key_path} ubuntu@${aws_eip.minecraft_ip.public_ip}"
}