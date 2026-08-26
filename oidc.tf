# AWS permits one OIDC provider per URL per account, so an account shared with another Terraform
# state cannot own this — whichever applies last wins. A dedicated organization makes it ours.
#
# The thumbprint is read from the live certificate, not pinned: a hardcoded fingerprint is a
# hardcoded expiry date.
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = data.tls_certificate.github_actions.url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.github_actions.certificates[*].sha1_fingerprint
}

# Plan-capable, not apply-capable. Applies are run by hand; CI exists to post a plan on a PR so the
# diff is reviewed before it is real. A role that could apply would make the review advisory.
data "aws_iam_policy_document" "github_plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Without this the role is assumable from any repository on GitHub, which is the single most
    # common way an OIDC role is misconfigured.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}/lakeworks-*:*",
        "repo:${var.github_owner}/terraform-aws-lakeworks-*:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name               = "lakeworks-github-plan"
  description        = "Assumed by GitHub Actions to run terraform plan and post the diff to a PR. Cannot apply."
  assume_role_policy = data.aws_iam_policy_document.github_plan_trust.json
}

resource "aws_iam_role_policy_attachment" "github_plan_read" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# A plan reads state and writes the lock. Without the write it cannot acquire one, and concurrent
# plans would race on the same key.
data "aws_iam_policy_document" "github_plan_state" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_plan_state" {
  name   = "state-access"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_state.json
}

# Planning a member account is a second hop: GitHub federates into this role, and this role assumes
# a read-only role in the account being planned. `ReadOnlyAccess` grants three STS actions —
# GetAccessKeyInfo, GetCallerIdentity and GetSessionToken — and `sts:AssumeRole` is not one of them,
# so without this every member-account plan fails at the hop rather than at the plan.
#
# Scoped by name pattern rather than to one role, because member-account roles are created by the
# repos that own those accounts and their names are not decided here. The grant is half the gate:
# a role is assumable only if its own trust policy also names this one, so a role that never opted
# in stays unreachable.
data "aws_iam_policy_document" "github_plan_assume" {
  statement {
    sid       = "AssumeMemberPlanRoles"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${aws_organizations_account.dev.id}:role/lakeworks-*-plan-role"]
  }
}

resource "aws_iam_role_policy" "github_plan_assume" {
  name   = "assume-member-plan-roles"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_assume.json
}
