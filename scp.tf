# One region, enforced. The cost model in cost.md assumes a single region, and a resource created
# in another is both invisible on the dashboards and outside the budget's blast radius.
#
# Deliberately narrow: global services have no region and would break under a blanket deny, so they
# are excluded by name rather than by guessing.
# `not_actions` only. A statement carries Action or NotAction, never both — setting `actions`
# alongside it emits an invalid document that Organizations rejects as malformed rather than
# describing which half is wrong.
data "aws_iam_policy_document" "region_lock" {
  statement {
    sid       = "DenyOutsideAllowedRegion"
    effect    = "Deny"
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region, "us-east-1"] # us-east-1 for CloudFront certs, Billing and CUR
    }

    # Global services have no region, so a blanket deny would lock them out entirely. Excluded by
    # name rather than by guessing at which calls carry aws:RequestedRegion.
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
