module "eks-alb-ingress" {
  count                   = var.option_alb_ingress_enabled ? 1 : 0
  source                  = "./terraform-aws-eks-alb-ingress"
  cluster_name            = local.cluster_name
  cluster_region          = var.AWS_REGION
  cluster_oidc_issuer_url = local.cluster_oidc_issuer_url
  cluster_vpc_id          = aws_vpc.cluster.id
  common_tags             = local.common_tags
  oidc_provider_arn       = local.oidc_provider_arn
  depends_on              = [aws_eks_cluster.eks-cluster]
}
