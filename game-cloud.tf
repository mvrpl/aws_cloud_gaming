locals {
  name = "cloud-game"
  region = "sa-east-1"
  access_key_id = "ACCESS_KEY"
  secret_key_id = "SECRET_KEY"
  tags = {
    Terraform = "true"
    Environment = "game"
  }
}

provider "aws" {
    access_key = local.access_key_id
    secret_key = local.secret_key_id
    region = local.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group_rule" "rdp_ingress" {
  type = "ingress"
  description = "Allow rdp connections (port 3389)"
  from_port = 3389
  to_port = 3389
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = module.security_group.this_security_group_id
}

resource "random_password" "password" {
  length = 12
  special = true
}

resource "aws_ssm_parameter" "password" {
  name = "${local.name}-administrator-password"
  type = "SecureString"
  value = random_password.password.result

  tags = local.tags
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name = local.name
  description = "Security group for example usage with EC2 instance with RDP"
  vpc_id = data.aws_vpc.default.id
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  name = local.name

  ami = "ami-09748ba96706dfe76"
  instance_type = "g4dn.xlarge"
  key_name = "GameCloudAWS"
  monitoring = false
  get_password_data = true
  vpc_security_group_ids = [module.security_group.this_security_group_id]
  subnet_id = tolist(data.aws_subnets.all.ids)[0]
  availability_zone = "${local.region}a"
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/windows_script.tpl", {
    password_ssm_parameter=aws_ssm_parameter.password.name
  })

  ebs_optimized = true

  tags = local.tags
}

output "instance_id" {
  value = module.ec2_instance.id
}

output "instance_ip" {
  value = module.ec2_instance.public_ip
}

output "instance_public_dns" {
  value = module.ec2_instance.public_dns
}

output "instance_username" {
  value = "Administrator"
}

output "instance_password" {
  value = random_password.password.result
  sensitive = true
}