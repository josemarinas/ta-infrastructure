locals {
  vpc_cidr  = "10.0.0.0/16"
}

provider "aws" {
  version = "~> 2.8"
  region  = "eu-west-1"
}

###########
### VPC ###
###########
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.15.0"
  name = "vpc-ta"
  cidr = local.vpc_cidr

  azs             = ["eu-west-1a"]
  # private_subnets = ["10.0.2.0/24"]
  public_subnets  = ["10.0.1.0/24"]

  database_subnet_assign_ipv6_address_on_creation = false
  elasticache_subnet_assign_ipv6_address_on_creation = false
  enable_classiclink = false
  enable_classiclink_dns_support = false
  intra_subnet_assign_ipv6_address_on_creation = false
  private_subnet_assign_ipv6_address_on_creation = false
  public_subnet_assign_ipv6_address_on_creation = false
  redshift_subnet_assign_ipv6_address_on_creation = false
}

##############
### QUEUES ###
##############
module "sqs-input" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "2.0.0"
  name = "ta-input-queue.fifo"
  fifo_queue = true
  visibility_timeout_seconds = 3
  tags = {
    Name = "ta-input-queue.fifo"
    Flow = "input"
  }
}

module "sqs-output" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "2.0.0"
  name = "ta-output-queue.fifo"
  fifo_queue = true
  visibility_timeout_seconds = 3
  tags = {
    Name = "ta-output-queue.fifo"
    Flow = "output"
  }
}

#################
### INSTANCES ###
#################
module "instance-echo-system" {
  instance_count = 2
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "2.8.0"
  ami = "ami-06358f49b5839867c" # Ubuntu bionic id
  instance_type = "t2.micro"
  name = "ta-worker"
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [
    module.allow-public-http-security-group.this_security_group_id, 
    module.allow-public-https-security-group.this_security_group_id,
    module.allow-public-ssh-security-group.this_security_group_id,
    module.allow-public-icmp-security-group.this_security_group_id
  ]
  associate_public_ip_address = true
  key_name = "key-ta"
  root_block_device = [
    {
      device_name = "/dev/sda1"
      volume_type = "gp2"
      volume_size = 8
      encrypted   = true
    },
  ]
  tags = {
    Function = "ta-worker"
  }
}

module "instance-frontend" {
  instance_count = 1
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "2.8.0"
  ami = "ami-06358f49b5839867c" # Ubuntu bionic id
  instance_type = "t2.micro"
  name = "ta-web-server"
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [
    module.allow-public-http-security-group.this_security_group_id, 
    module.allow-public-https-security-group.this_security_group_id,
    module.allow-public-ssh-security-group.this_security_group_id,
    module.allow-public-icmp-security-group.this_security_group_id
  ]
  associate_public_ip_address = true
  key_name = "key-ta"
  root_block_device = [
    {
      device_name = "/dev/sda1"
      volume_type = "gp2"
      volume_size = 8
      encrypted   = true
    },
  ]
  tags = {
    Function = "ta-web-server"
  }
}

##################
### S3 BUCKETS ###
##################
resource "aws_s3_bucket" "ta" {
  force_destroy = true
  bucket = "ta-bucket-josemarinas"
  region = "eu-west-1"
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "DELETE"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
 }

#######################
### SECURITY GROUPS ###
#######################
module "allow-public-http-security-group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.1.0"
  name = "allow-public-http-security-group"
  vpc_id = module.vpc.vpc_id
  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["http-80-tcp"]
  egress_cidr_blocks      = ["0.0.0.0/0"]
  egress_rules            = ["all-all"]
}

module "allow-public-https-security-group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.1.0"
  name = "allow-public-https-security-group"
  vpc_id = module.vpc.vpc_id
  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["https-443-tcp"]
  egress_cidr_blocks      = ["0.0.0.0/0"]
  egress_rules            = ["all-all"]
}

module "allow-public-ssh-security-group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.1.0"
  name = "allow-public-ssh-security-group"
  vpc_id = module.vpc.vpc_id
  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["ssh-tcp"]
  egress_cidr_blocks      = ["0.0.0.0/0"]
  egress_rules            = ["all-all"]
}

module "allow-public-icmp-security-group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.1.0"
  name = "allow-public-icmp-security-group"
  vpc_id = module.vpc.vpc_id
  ingress_cidr_blocks      = ["0.0.0.0/0"]
  ingress_rules            = ["all-icmp"]
  egress_cidr_blocks      = ["0.0.0.0/0"]
  egress_rules            = ["all-all"]
}

###############
### SSH KEY ###
###############
resource "aws_key_pair" "ta" {
  key_name   = "key-ta"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC1AH8ri8JB7kUFQGGmR3YQI9W9Pbm8My/upb8JWlawgq5E5CGf57KhKSOKKVs+4KcWkRnpc/5F6K/cr3XPAKVo5dmpEMXnrGWFKiqrUK1j4ZMBt69O7jvS0BJ7lTWyM5ztpPbQupVRKt8Zg3D731/qWMHlqed84cxUCBXUP2rfMyNM9D/PJIcF7+Q2VyES9s67ejoS7EyS2T/KdLUnFDRYkgs2WtML/lO/BLRShurvQdrMuvGBk8o26zErVusSx4BMfm4puPU69hb1cPDAHFOlXP/xPTF+HDbctNGK3+IK9f3B02Jz+gCILXCEThVCamp4fgyEWyPiIRjOkN92lsER jose@jose-MSI"
}

