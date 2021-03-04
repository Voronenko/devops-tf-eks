locals {
  subnets = [
    aws_subnet.eks-private.id,
    aws_subnet.eks-private-2.id,
  ]

  node_role_arn = "arn:aws:iam::152620932177:role/staging20201020121930440900000009"
}

#####
# EKS Node Group
#####
module "eks-node-group" {
  source = "git::https://github.com/softasap/terraform-aws-eks-node-group.git?ref=develop"

  node_group_name = "spot-nodegroup"
  node_role_arn   = aws_iam_role.EKSNodeRole.arn

  cluster_name = local.cluster_name
  subnet_ids   = flatten(local.subnets)

  desired_size = 1
  max_size     = 3
  min_size     = 1

  //  ec2_ssh_key = "voronenko_info"
  //  kubernetes_labels = {
  //  }

  instance_types = ["t3.large"]

  # keep this synchronized for
  # https://github.com/awsdocs/amazon-eks-user-guide/blob/master/doc_source/eks-linux-ami-versions.md
  ami_release_version = "1.18.9-20210208"

  capacity_type = "SPOT"

  disk_size = 100

  create_iam_role = false

  launch_template = {}

  tags = {
    Environment = var.CLUSTER_NAME
  }

  depends_on = [aws_eks_cluster.eks-cluster]
}
