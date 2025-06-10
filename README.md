# Minecraft Server with AWS and Terraform Guide (2025)
This is a quick guide for setting up a Minecraft server with AWS and Terraform.

### Prerequisites
- AWS Account (this tutorial uses a student account)
- Terraform
- Minecraft Account

## Part 1: Get AWS Credentials

1. Go to the Canvas page for your AWS Academy Learner Lab, then go to Modules. Click "Launch AWS Academy Learner Lab".

2. Click the "Start Lab" button on the top right of the window. Once the red circle at the top left of the window next to "AWS" turns green, the lab has fully started.

3. Click the "AWS Details" button. This should bring up your access key, secret access key, and session token. Save these credentials. You will need to copy and paste them later.

## Part 2: Getting Started with Terraform

4. Open your console. Verify that you have Terraform and the AWS CLI installed by typing the following commands:

    + `terraform version`
    + `aws -- version`

    This tutorial uses Terraform v1.12.1 and aws-cli 2.27.22.

5. Type `aws configure`. The console will ask for your AWS Access Key ID and your AWS Secret Access Key. Paste the credentials you saved from **Part 1**. When prompted to type a default region name, choose the region closest to your location. When prompted to provide a default output format, just press Enter on your keyboard.

    + You can verify that AWS has been configured properly by going to your user folder in your system and checking the ".aws" folder within it. There should be two files: "config" and "credentials". The "config" file should contain your region and the "credentials" file should show your AWS credentials.
    + **IMPORTANT**: If your AWS credentials include an aws_session_token, copy and paste it into the credentials file. Your access key, secret key, and session token will change if you restart the lab on Canvas. Make sure that your credentials file contains your current credentials in order to make the Minecraft server run properly.

## Part 3: Coding with Terraform

6. Create a "main.tf" file and a "variables.tf" file. Put them in a location within your directory.

    + You can verify that you have placed these files in a suitable location by using the "ls" command. If this shows the files you created, you did this step correctly.

7. Copy the following code into main.tf:
```
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
    region = "us-west-2" # choose the region closest to your location
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
```

8. Copy the following code into variables.tf:
```
variable "aws_region"       { default = "us-west-2" } # choose the reason closest to your location
variable "aws_profile"      { default = "terraform" }
variable "public_key_path" {
    type    = string
    default = "~/.ssh/id_rsa.pub"
}
variable "vpc_id" {
    type        = string
    default     = ""
}
```

9. Type the following commands in the console:
```
terraform init
terraform validate
terraform plan
terraform apply
```

## Part 4: Verification and Finalization

10. Retrieve your public IP with the following command: `terraform output minecraft_server_public_ip`

11. Use your public IP to connect with the following command to connect to your instance's public IP address:
`nmap -sV -Pn -p T:25565 <instance_public_ip>`

    + Note: If you are working on a Windows machine, you may need to install nmap first.

    This will tell you if you have set up everything correctly.

### Time to play Minecraft!

12. Login to your Minecraft account on the game's launcher and launch the latest version of Minecraft.

13. Click "Multiplayer" and then "Add Server". In the Server Address, paste your Minecraft server's public IP. Click "Done".

14. Wait for your game to finish connecting to the server. Once the connection is complete, you should see "0/20" to the right of the server name. This shows that there are currently 0 players online out of the maximum possible of 20.

15. Click on the server from the list, click "Join Server", and have fun!