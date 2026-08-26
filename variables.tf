variable "region" {
  description = "The one region. An SCP denies the others."
  type        = string
  default     = "us-east-2"
}

variable "management_account_id" {
  description = "The lakeworks Organization management account. Holds billing, state and identity, and no workload — SCPs cannot reach a management account, so nothing that needs guarding may live in it. No default: this must be stated, and providers.tf refuses to run against a different account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be exactly 12 digits."
  }
}

variable "state_bucket" {
  description = "Terraform state bucket, created by hand before the first init and adopted here with an import block. Must match the -backend-config passed to terraform init."
  type        = string

  validation {
    condition     = can(regex("^lakeworks-tfstate-[0-9]{12}$", var.state_bucket))
    error_message = "state_bucket must be lakeworks-tfstate-<12-digit-account-id>."
  }
}

variable "dev_account_email" {
  description = "Unique email for the dev member account. AWS refuses an address already used by any account, and closing an account consumes its address for roughly 90 days. A Fastmail alias is the low-friction route."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.dev_account_email))
    error_message = "dev_account_email must be a single valid email address."
  }
}

variable "github_owner" {
  description = "GitHub owner whose lakeworks repos may assume the plan role."
  type        = string
  default     = "datapointchris"
}

variable "monthly_budget_usd" {
  description = "Actual-spend alarm threshold. cost.md targets under $20 steady state, with exercise months allowed to reach $40."
  type        = number
  default     = 20
}

variable "alert_email" {
  description = "Where budget and anomaly alerts land."
  type        = string
}
