# One region, enforced. The cost model in cost.md assumes a single region, and a resource created
# in another is both invisible on the dashboards and outside the budget's blast radius.
#
# Deliberately narrow: global services have no region and would break under a blanket deny, so they
# are excluded by name rather than by guessing.
data "aws_iam_policy_document" "region_lock" {
  statement {
    sid       = "DenyOutsideAllowedRegion"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region, "us-east-1"] # us-east-1 for CloudFront certs, Billing and CUR
    }

    not_actions = [
      "iam:*",
      "organizations:*",
      "sts:*",
      "budgets:*",
      "ce:*",
      "cloudfront:*",
      "route53:*",
      "support:*",
      "health:*",
      "s3:ListAllMyBuckets",
    ]
  }
}

resource "aws_organizations_policy" "region_lock" {
  name        = "lakeworks-region-lock"
  description = "Deny anything outside us-east-2, excepting global services and the us-east-1-only APIs."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.region_lock.json
}

resource "aws_organizations_policy_attachment" "region_lock_dev" {
  policy_id = aws_organizations_policy.region_lock.id
  target_id = aws_organizations_account.dev.id
}
