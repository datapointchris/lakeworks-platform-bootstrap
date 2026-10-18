# Bootstrap runs by hand, in the lakeworks management account, a handful of times ever. It is
# deliberately not wired to the CI OIDC role: giving a workflow organizations:CreateAccount would
# let a compromised run create AWS accounts on the bill, which is why bootstrap is a separate repo
# from platform-core.
#
# No assume_role here. Credentials come from the AWS profile you run it with, and that profile is
# already inside the management account — there is nothing to assume into. See the README for the
# one-time sequence that creates it.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      "lakeworks:env"        = "management"
      "lakeworks:domain"     = "platform"
      "lakeworks:pipeline"   = "bootstrap"
      "lakeworks:layer"      = "none"
      "lakeworks:owner"      = "platform-team"
      "lakeworks:managed-by" = "terraform"
    }
  }
}

provider "tls" {}

data "aws_caller_identity" "current" {}

# Names the wrong account before anything is created in it. A stale profile would otherwise apply
# the lakeworks organization into whatever account the credentials happen to name, and creating an
# organization is not an action to discover after the fact. A failed check is a warning: the plan
# prints both account ids and carries on, through apply as well. So the plan's warnings are read
# before it is applied.
check "running_in_the_management_account" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.management_account_id
    error_message = "Credentials are for account ${data.aws_caller_identity.current.account_id}, but management_account_id is ${var.management_account_id}. Check your AWS profile."
  }
}
