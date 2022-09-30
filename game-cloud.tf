locals {
  name = "cloud-game"
  region = "sa-east-1"
  tags = {
    Terraform = "true"
    Environment = "game"
  }
}

variable "aws_access" {type = string}
variable "aws_secret" {type = string}

provider "aws" {
    access_key = var.aws_access
    secret_key = var.aws_secret
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

resource "aws_iam_policy" "password_get_parameter_policy" {
  name = "${local.name}-password-get-parameter-policy"
  policy = <<EOF
{
  "Version": "1.0",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "${aws_ssm_parameter.password.arn}"
    }
  ]
}
EOF
}

data "aws_key_pair" "key_pem" {}

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
  key_name = data.aws_key_pair.key_pem.key_name
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

  root_block_device = [{
    volume_type = "gp2"
    volume_size = 42
    encrypted = false
    delete_on_termination = true
  }]

  tags = local.tags
}

resource "aws_ebs_snapshot_import" "game_vhd" {
  disk_container {
    format = "VHD"
    user_bucket {
      s3_bucket = "hd-images"
      s3_key = "GAME_DISK.vhd"
    }
  }

  role_name = "game-disk-image-import"

  tags = local.tags
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/xvda"
  volume_id = aws_ebs_volume.game_disk.id
  instance_id = module.ec2_instance.id
}

resource "aws_ebs_volume" "game_disk" {
  availability_zone = "${local.region}a"
  size = 256
  snapshot_id = aws_ebs_snapshot_import.game_vhd.id
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