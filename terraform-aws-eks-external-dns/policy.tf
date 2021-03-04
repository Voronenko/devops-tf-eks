resource "aws_iam_policy" "allow_writing_dns_zone" {
  # ... other configuration ...
  name        = "allow_writing_dns_zone_${var.cluster_name}"
  policy      = data.aws_iam_policy_document.allow_writing_dns_zone.json
  description = "Managing ${var.domain} Route53 records"
}


data "aws_iam_policy_document" "allow_writing_dns_zone" {

  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.dns_zone.zone_id}"]
    effect    = "Allow"
  }

  statement {
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.dns_zone.zone_id}"]
    effect    = "Allow"
  }

  statement {
    actions   = ["route53:GetChange"]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["route53:ListHostedZones"]
    resources = ["*"]
    effect    = "Allow"
  }

}
