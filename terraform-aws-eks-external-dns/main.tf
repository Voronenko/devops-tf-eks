//resource "aws_iam_policy" "allow_writing_acme_zone" {
//  # ... other configuration ...
//  name   = "allow_writing_staging_acme_zone_${var.CLUSTER_NAME}"
//  policy = data.aws_iam_policy_document.allow_writing_acme_zone.json
//  description = "Managing ${var.domain} Route53 records"
//}

data "aws_iam_policy" "allow_writing_acme_zone" {
  arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/allow_writing_zone_${var.cluster_name}"
  depends_on = [aws_iam_policy.allow_writing_dns_zone]
}

data "aws_iam_policy_document" "allow_writing_zone" {
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

# Important(!) below prevents quite powerful role to be used on kube
# by any account except named in a designated namespace
data "aws_iam_policy_document" "external_dns_assume" {
  depends_on = [var.ingress_alb_k8s_dummy_dependency]

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"

      values = [
        "system:serviceaccount:${var.external_dns_k8s_namespace}:${var.external_dns_k8s_service_account_name}",
      ]
    }

    effect = "Allow"
  }
}

# These things are a bit confusing (on Amazon side, not Terraform),
# but you have your policies backwards.
# The one with "sts:AssumeRole" needs to be assigned to the `assume_role_policy` field of `aws_iam_role`
# and the one with the `Resource` goes under `policy` in `aws_iam_role_policy`.

resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = data.aws_iam_policy.allow_writing_acme_zone.arn
}

resource "helm_release" "external_dns" {
  name       = var.external_dns_helm_release_name
  repository = var.external_dns_helm_repo_url
  chart      = var.external_dns_helm_chart_name
  namespace  = var.external_dns_k8s_namespace
  version    = var.external_dns_helm_chart_version

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = var.external_dns_k8s_service_account_name
  }

  set {
    name  = "aws.zoneType"
    value = "public"
  }

  set {
    name  = "txtOwnerId"
    value = "externaldns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }

  # AWS region of k8s cluster, required if ec2metadata is unavailable from controller pod
  set {
    name  = "aws.region"
    value = var.cluster_region
  }

  dynamic "set" {
    for_each = var.external_dns_settings

    content {
      name  = set.key
      value = set.value
    }
  }
}
