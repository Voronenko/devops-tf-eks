data "aws_eks_cluster" "eks-cluster" {
  name = var.cluster_name
}
