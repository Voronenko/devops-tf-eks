data "aws_caller_identity" "current" {}

data "aws_route53_zone" "dns_zone" {
  name = var.domain
}
