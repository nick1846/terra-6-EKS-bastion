provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "aws_key_pair" "ec2-user-public" {
  key_name   = var.my_key_name
  public_key = var.my_publickey
}


data "aws_eks_cluster" "cluster" {
  name = module.my-eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.my-eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

module "my_vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  cidr                 = var.my_vpc_cidr
  azs                  = var.my_vpc_azs
  private_subnets      = var.my_vpc_private_subnets
  public_subnets       = var.my_vpc_public_subnets
  enable_dns_hostnames = var.my_dns_hostnames_bool
  enable_nat_gateway   = var.my_vpc_nat_gateway_bool
  single_nat_gateway   = true
  enable_dns_support   = true
  vpc_tags             = var.my_tags
  public_subnet_tags   = var.my_public_subnets_tags
  private_subnet_tags  = var.my_private_subnets_tags

}


resource "aws_security_group_rule" "eks_ingress_localhost" {
  type        = "ingress"
  description = "Allow traffic from localhost"

  # Allow inbound traffic from your localhost external IP to the EKS. 
  #Replace A.B.C.D/32 with your real IP. Use service like "icanhazip.com"

  cidr_blocks       = ["A.B.C.D/32"]  
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.my-eks.cluster_security_group_id
}

resource "aws_security_group_rule" "eks_ingress_bastion" {
  type        = "ingress"
  description = "Allow traffic from bastion host"

  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.my-eks.cluster_security_group_id
  source_security_group_id = aws_security_group.sg_bastion.id
}



module "my-eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "my-cluster"
  cluster_version = "1.17"
  subnets                         = module.my_vpc.private_subnets 
  vpc_id                          = module.my_vpc.vpc_id
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  

  node_groups = {

    private = {

      subnets          = module.my_vpc.private_subnets
      desired_capacity = 2
      max_capacity     = 5
      min_capacity     = 1
      instance_types   = ["t2.micro"]
      k8_labels = {
        Environment = "private"
      }
    }
  }
}

resource "aws_security_group" "sg_bastion" {
  name        = "sg_bastion"
  description = "Security group for bastion host"
  vpc_id      = module.my_vpc.vpc_id

  ingress {
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
}


resource "aws_security_group_rule" "ss_bastion_ingres_eks" {
  type        = "ingress"
  description = "Allow traffic from eks"

  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.sg_bastion.id
  source_security_group_id = module.my-eks.cluster_security_group_id
}


#AMI data source for bastion host

data "aws_ami" "my_ami" {
  most_recent = var.most_recent_bool
  filter {
    name   = var.ami_tag_type
    values = var.ami_value
  }
  owners = var.ami_owner
}


#launch configuration and autoscaling group for bastion host in public subnet

resource "aws_launch_configuration" "asg_lconf" {
  name            = "my_launch_conf"
  image_id        = data.aws_ami.my_ami.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.sg_bastion.id]
  key_name        = var.my_key_name
  lifecycle {
    create_before_destroy = true
  }
}


module "asg" {
  source                    = "terraform-aws-modules/autoscaling/aws"
  name                      = "bastion_host"
  create_lc                 = false
  use_lc                    = true
  launch_configuration      = aws_launch_configuration.asg_lconf.name
  vpc_zone_identifier       = module.my_vpc.public_subnets 
  health_check_type         = "EC2"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

  tags = [
    {
      key                 = "Enviroment"
      value               = "BostionHost"
      propagate_at_launch = true
    }
  ]
}