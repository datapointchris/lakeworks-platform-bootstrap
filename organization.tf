# The Organization. Created here rather than in the console so the feature set, the enabled policy
# types and the delegated services are reviewable rather than remembered.
resource "aws_organizations_organization" "this" {
  feature_set = "ALL" # ALL, not CONSOLIDATED_BILLING — SCPs require it

  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]

  # Services that need to see across the organization. Each one added here is a service that can
  # read member-account data, so the list stays short and every entry has a reason.
  aws_service_access_principals = [
    "sso.amazonaws.com",           # IAM Identity Center, the login path
    "account.amazonaws.com",       # alternate contacts on member accounts
    "cloudtrail.amazonaws.com",    # one organization trail rather than one per account
    "ram.amazonaws.com",           # Resource Access Manager — how Lake Formation shares
    "servicequotas.amazonaws.com", # quota increases without a ticket per account
  ]

  # Lake Formation has no trusted-access principal of its own — Organizations rejects
  # `lakeformation.amazonaws.com` as unrecognized. Cross-account data sharing is a RAM
  # operation, so `ram.amazonaws.com` above is what enables the data-mesh mechanism.

  lifecycle {
    # An organization is not a thing to lose to a stray plan. Removing it would orphan every member
    # account and cannot be undone by re-applying.
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "dev" {
  name  = "lakeworks-dev"
  email = var.dev_account_email

  # The role this account trusts the management account to assume into. Terraform for every other
  # lakeworks repo arrives through it.
  role_name = "OrganizationAccountAccessRole"

  # Terraform removes the account from state rather than closing it. That is the safe default and
  # it is why this is not `prevent_destroy` — a destroy here is recoverable, unlike the org.
  close_on_deletion = false

  parent_id = aws_organizations_organization.this.roots[0].id

  tags = {
    "lakeworks:env" = "dev"
  }

  lifecycle {
    # Changing the email address of an existing account is not something AWS supports in place;
    # Terraform would try to replace the account, which is exactly the ~90-day mistake.
    ignore_changes = [email]
  }
}
