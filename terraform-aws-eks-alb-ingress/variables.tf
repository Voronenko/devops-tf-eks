variable "cluster_name" {
  type = string
}

variable "cluster_region" {
  type = string
}

variable "cluster_vpc_id" {
  type = string
}

variable "common_tags" {
}

variable "cluster_oidc_issuer_url" {
}

variable "oidc_provider_arn" {
}


variable "ingress_alb_helm_chart_name" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "ingress_alb_helm_chart_version" {
  type    = string
  default = "1.0.3"
}

variable "ingress_alb_helm_release_name" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "ingress_alb_helm_repo_url" {
  type    = string
  default = "https://aws.github.io/eks-charts"
}

variable "ingress_alb_k8s_namespace" {
  type = string
  # kube-system is recommended over alb-ingress
  # per https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
  default     = "kube-system"
  description = "The k8s namespace in which the alb-ingress service account has been created"
}

variable "ingress_alb_k8s_service_account_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "The k8s alb-ingress service account name, should match to helm chart expectations"
}


variable "ingress_alb_k8s_dummy_dependency" {
  default     = null
  description = "TODO: eliminatem allows dirty re-drop"
}

variable "ingress_alb_settings" {
  type        = map(any)
  default     = {}
  description = "Additional settings for Helm chart check https://artifacthub.io/packages/helm/helm-incubator/aws-alb-ingress-controller"
}
