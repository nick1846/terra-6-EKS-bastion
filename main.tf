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
  load_config_file       = false
}

module "my_vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  name                 = var.my_vpc_name
  cidr                 = var.my_vpc_cidr
  azs                  = var.my_vpc_azs
  private_subnets      = var.my_vpc_private_subnets
  public_subnets       = var.my_vpc_public_subnets
  enable_dns_hostnames = var.my_dns_hostnames_bool
  enable_nat_gateway   = var.my_vpc_nat_gateway_bool
  vpc_tags             = var.my_vpc_tags
  public_subnet_tags   = var.my_public_subnets_tags
  private_subnet_tags  = var.my_private_subnets_tags
  igw_tags             = var.my_igw_tags

}

module "my-eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "my-cluster"
  cluster_version = "1.17"
  subnets         = [ module.my_vpc.private_subnets[0], module.my_vpc.public_subnets[1] ]
  vpc_id          = module.my_vpc.vpc_id

  node_groups = {

    public = {
      subnets          = [ module.my_vpc.public_subnets[1] ]
      desired_capacity = 1
      max_capacity     = 5
      min_capacity     = 1
      instance_type    = "t2.micro"
      k8_labels = {
        Environment = "public"
      }
    }

    private = {
      subnets          = [ module.my_vpc.private_subnets[0] ]
      desired_capacity = 1
      max_capacity     = 5
      min_capacity     = 1
      instance_type    = "t2.micro"
      k8_labels = {
        Environment = "private"
      }
    }  
  }
}