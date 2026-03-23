# GitHub Actions OIDC provider — account-scoped, created once
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Trust policy — restricts to pull_request events on this repo only
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope to pull_request events on this repo — plan-only, not apply
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:pull_request"]
    }
  }
}

# Read-only policy — sufficient for tofu plan across all stacks
data "aws_iam_policy_document" "github_actions_plan" {
  statement {
    sid    = "EC2ReadOnly"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:List*",
      "ec2:Get*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EKSReadOnly"
    effect = "Allow"
    actions = [
      "eks:Describe*",
      "eks:List*",
      "eks:AccessKubernetesApi",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMReadOnly"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "STSReadOnly"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "github_actions_plan" {
  name               = "github-actions-plan"
  description        = "Assumed by GitHub Actions pull_request workflows for tofu plan"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

resource "aws_iam_role_policy" "github_actions_plan" {
  name   = "github-actions-plan"
  role   = aws_iam_role.github_actions_plan.id
  policy = data.aws_iam_policy_document.github_actions_plan.json
}
