resource "kubernetes_namespace" "alb_ingress" {
  depends_on = [var.ingress_alb_k8s_dummy_dependency]
  count      = (var.ingress_alb_k8s_namespace != "kube-system") ? 1 : 0

  metadata {
    name = var.ingress_alb_k8s_namespace
  }
}

resource "aws_iam_policy" "alb_ingress" {
  depends_on  = [var.ingress_alb_k8s_dummy_dependency]
  name        = "${var.cluster_name}-alb-ingress"
  path        = "/"
  description = "ALBIngressControllerIAMPolicy for alb-ingress service"

  policy = templatefile("${path.module}/files/iam-policy.json", {
  })
}

# Important(!) below prevents quite powerful role to be used on kube
# by any account except named in a designated namespace
data "aws_iam_policy_document" "alb_ingress_assume" {
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
        "system:serviceaccount:${var.ingress_alb_k8s_namespace}:${var.ingress_alb_k8s_service_account_name}",
      ]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role" "alb_ingress" {
  depends_on         = [var.ingress_alb_k8s_dummy_dependency]
  name               = "${var.cluster_name}-alb-ingress"
  assume_role_policy = data.aws_iam_policy_document.alb_ingress_assume.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy_attachment" "alb_ingress" {
  depends_on = [var.ingress_alb_k8s_dummy_dependency]
  role       = aws_iam_role.alb_ingress.name
  policy_arn = aws_iam_policy.alb_ingress.arn
}


resource "helm_release" "alb_ingress" {
  depends_on = [var.ingress_alb_k8s_dummy_dependency]
  name       = var.ingress_alb_helm_release_name
  repository = var.ingress_alb_helm_repo_url
  chart      = var.ingress_alb_helm_chart_name
  namespace  = var.ingress_alb_k8s_namespace
  version    = var.ingress_alb_helm_chart_version

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_ingress.arn
  }

  # AWS region of k8s cluster, required if ec2metadata is unavailable from controller pod
  set {
    name  = "region"
    value = var.cluster_region
  }

  # AWS VPC ID of k8s cluster, required if ec2metadata is unavailable from controller pod
  set {
    name  = "vpcId"
    value = var.cluster_vpc_id
  }

  dynamic "set" {
    for_each = var.ingress_alb_settings

    content {
      name  = set.key
      value = set.value
    }
  }
}
