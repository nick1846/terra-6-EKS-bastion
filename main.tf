provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}


#my vpc

module "my_vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  name                 = var.my_vpc_name
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

####################################

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

#my eks 

module "my-eks" {
  source                          = "terraform-aws-modules/eks/aws"
  cluster_name                    = "my-cluster"
  cluster_version                 = "1.17"
  subnets                         = module.my_vpc.private_subnets
  vpc_id                          = module.my_vpc.vpc_id
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true


  node_groups = {

    private = {
      desired_capacity = 2
      max_capacity     = 5
      min_capacity     = 1
      instance_types   = ["t2.micro"]
    }
  }

}





############################################

#my key pair for bastion host

resource "aws_key_pair" "ec2-user-public" {
  key_name   = var.my_key_name
  public_key = var.my_publickey
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

#launch template and autoscaling group for bastion host in public subnets

resource "aws_launch_template" "asg_lt" {
  name                   = "bastion_launch_template"
  image_id               = data.aws_ami.my_ami.id
  instance_type          = "t2.micro"
  key_name               = var.my_key_name
  vpc_security_group_ids = [aws_security_group.sg_bastion_ssh.id, aws_security_group.sg_bastion_eks.id]
  user_data              = filebase64("userdata.sh")
}



module "asg" {
  source                    = "terraform-aws-modules/autoscaling/aws"
  name                      = "bastion_host"
  create_lt                 = false
  use_lt                    = true
  launch_template           = aws_launch_template.asg_lt.name
  lt_version                = "$Latest"
  vpc_zone_identifier       = module.my_vpc.public_subnets
  health_check_type         = "EC2"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

}