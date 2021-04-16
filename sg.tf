#my security groups 

resource "aws_security_group_rule" "eks_ingress_localhost" {
  type        = "ingress"
  description = "Allow traffic from localhost"

  # Allow inbound traffic from your localhost external IP to the EKS. 
  #Replace A.B.C.D/32 with your real IP. Use service like "ipv4.icanhazip.com"

  cidr_blocks       = ["A.B.C.D/32"]
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.my-eks.cluster_security_group_id
}

resource "aws_security_group_rule" "rule_eks_ingress_bastion" {
  type        = "ingress"
  description = "Allow traffic from bastion host"

  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.my-eks.cluster_security_group_id
  source_security_group_id = aws_security_group.sg_bastion_eks.id
}

resource "aws_security_group" "sg_bastion_ssh" {
  name        = "sg_bastion_ssh"
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

  tags = {
    Name = "sg_bastion_ssh"
  }
}

resource "aws_security_group" "sg_bastion_eks" {
  name        = "sg_bastion_eks"
  description = "Security group for bastion host to communicate with eks"
  vpc_id      = module.my_vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_bastion_eks"
  }
}


resource "aws_security_group_rule" "rule_bastion_ingress_eks" {
  type        = "ingress"
  description = "Allow traffic from eks"

  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_bastion_eks.id
  source_security_group_id = module.my-eks.cluster_security_group_id
}
