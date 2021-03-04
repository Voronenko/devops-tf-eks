variable "domain" {
}

variable "cluster_name" {
  type = string
}

variable "cluster_region" {
  type = string
}

variable "common_tags" {
}

variable "oidc_provider_arn" {
}

variable "cluster_oidc_issuer_url" {
}

variable "ingress_alb_k8s_dummy_dependency" {
  default     = null
  description = "TODO: eliminate allows dirty re-drop"
}

variable "external_dns_helm_chart_name" {
  type    = string
  default = "external-dns"
}

variable "external_dns_helm_chart_version" {
  type    = string
  default = "3.5.1"
}

variable "external_dns_helm_release_name" {
  type    = string
  default = "external-dns"
}

variable "external_dns_helm_repo_url" {
  type    = string
  default = "https://charts.bitnami.com/bitnami"
}

variable "external_dns_k8s_namespace" {
  type        = string
  default     = "kube-system"
  description = "The k8s namespace in which the alb-ingress service account has been created"
}

variable "external_dns_k8s_service_account_name" {
  type        = string
  default     = "external-dns"
  description = "The k8s external-dns service account name, ideally should match to helm chart expectations"
}

variable "external_dns_settings" {
  type        = map(any)
  default     = {}
  description = "Additional settings for external-dns helm chart check https://github.com/bitnami/charts/tree/master/bitnami/external-dns"
}
