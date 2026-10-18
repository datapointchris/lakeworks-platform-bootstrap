# lakeworks-platform-bootstrap

Terraform for what must exist before Terraform can manage anything else in lakeworks: the AWS
Organization, the `dev` member account, the state bucket, the region-lock SCP, the GitHub OIDC
provider, the plan-only CI role and the billing guardrails.

**It is applied by hand, a handful of times ever.** Everything inside `dev` belongs to
`lakeworks-platform-core` and the pipeline repos. They apply into the account this repo creates.

## Install

It needs Terraform at the version `versions.tf` requires, the AWS CLI, and `gh` for the CI
variables.

```bash
git clone https://github.com/datapointchris/lakeworks-platform-bootstrap.git
cd lakeworks-platform-bootstrap
terraform init -backend=false    # providers only, so it reaches no AWS account
terraform validate               # proves the configuration is valid, with no credentials
```

## Starting from scratch

An AWS account starts with only a root user and no credential to act with. So the first steps
happen in the console.

1. **Sign up the management account on the Paid plan.** A Free plan account closes automatically at
   six months or when its credits run out, whichever comes first. AWS deletes it 90 days later
   unless it is upgraded. An account inside an organization is on the Paid plan, so `dev` never
   faces the choice.
2. **Give each account a real email alias, not a plus-address.** A root email is load-bearing for
   the life of the account. AWS refuses an address another account already holds. The management
   account takes one. `dev` takes another, as `dev_account_email`.
3. **Turn on MFA for the root user, then stop using root.**
4. **Create the Terraform credential.** As root, create one IAM user with `AdministratorAccess` and
   MFA, and an access key for it.

Then, from a shell in the clone:

```bash
aws configure --profile lakeworks             # the access key from step 4
export AWS_PROFILE=lakeworks                  # every command below runs as that user
aws sts get-caller-identity                   # confirm the account id before anything else runs

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)    # the management account
BUCKET="lakeworks-tfstate-${ACCOUNT}"         # the one name state_bucket's validation accepts

# The state bucket, configured as state.tf declares it, for the first apply to adopt
aws s3api create-bucket --bucket "$BUCKET" --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2        # the region backend.tf names
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled                         # a bad apply stays recoverable
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

cp terraform.tfvars.example terraform.tfvars        # gitignored; fill in ids and emails
terraform init -backend-config="bucket=${BUCKET}"   # the partial backend gets its bucket here
terraform plan -out=bootstrap.tfplan                # read it, warnings included
terraform apply bootstrap.tfplan                    # adopts the bucket and creates everything else
terraform plan                                      # "No changes" proves it converged
```

**The bucket name is supplied at init, never written into `backend.tf`.** It carries the management
account id, which does not exist until the account does. In `terraform.tfvars`,
`management_account_id` takes `$ACCOUNT`. `state_bucket` takes `$BUCKET`, and must match the
`-backend-config`.

**`github_owner` and `github_owner_id` default to this repository's owner.** A fork sets both in
`terraform.tfvars`. `gh api users/<owner> --jq .id` prints the id.

**The account check warns and does not stop.** `providers.tf` compares the credentials' account with
`management_account_id` in a `check` block. Terraform reports a failed `check` as a warning and
carries on, through `apply` as well. So `aws sts get-caller-identity` is the real interlock. Read
the plan's warnings before applying it. Creating an organization in the wrong account is not
something to discover afterwards.

**The state bucket is made by hand because it holds the state that manages it.** The `import` blocks
in `state.tf` adopt it on the first apply. On every later apply they are no-ops. They stay in the
file as the record of how the bucket got here. Never make the first apply create it.

**Two steps follow the apply.** SNS emails a confirmation to `alert_email`. Budget alerts reach no
one until it is confirmed. Cost anomaly detection is off by default. Cost Explorer has to be enabled
once in the Billing console, which no API can do. Its data then takes up to 24 hours to exist. After
that, set `enable_cost_anomaly_detection = true` and apply again.

**The access key is the weakest part of this setup, and deliberately so.** Something has to hold the
first credential. That key is the thing worth guarding.

## The management account holds no workload, because no SCP reaches it

```text
  management
    billing · Organizations · state bucket
    OIDC provider · plan role · budgets
    no workload
      └── dev     every workload, region-locked
```

The organization is standalone. No pre-existing account is promoted into it.

**Service control policies do not apply to the management account.** Anything living there is
permanently outside every guardrail, including the region lock. An account holding real
infrastructure is exactly what must not be the org root. A bucket or a role added here "just for
now" makes the guardrails decorative.

The dedicated account also owns its GitHub OIDC provider outright. AWS permits one per URL per
account. A shared account would force one Terraform state to reference what another manages.

## A separate repo from platform-core, so CI never holds `organizations:CreateAccount`

The split is about CI credentials, not tidiness.

`lakeworks-platform-core` plans in GitHub Actions. If account creation lived in its root module, the
CI role would need `organizations:CreateAccount`. A compromised workflow could then create AWS
accounts on the bill. Here a person creates the account. The CI role never holds that permission.

The OIDC provider is the boundary case. It lives here, because CI cannot run anything until it
exists.

## The first apply puts the guardrails up before anything can spend

```text
MANAGEMENT                                   DEV (created here)
  Organization, feature_set = ALL              account lakeworks-dev
  SCP lakeworks-region-lock                    OrganizationAccountAccessRole
  S3 lakeworks-tfstate-<account>, adopted      region-lock SCP attached
  OIDC provider for GitHub Actions             (everything else is platform-core's)
  IAM lakeworks-github-plan  ← plan only
  SNS lakeworks-billing-alerts
  Budgets: actual, and forecast at double
  Cost Anomaly Detection  ← once enabled
```

Nothing should be able to spend before the alarm that watches spending exists. Billing is
management-level. That is why the budgets live here, rather than with the rest of the observability
work in `lakeworks-platform-core`.

The actual-spend budget alarms at `monthly_budget_usd`. The forecast budget alarms at twice that.
The forecast is the one that catches a runaway, because it fires while the job is still running.
Neither budget carries a cost filter. The account boundary separates spend more accurately than a
tag filter, because it catches resources nobody remembered to tag.

The anomaly subscription alerts on absolute dollars, not a percentage. At this spend level a 200%
anomaly is a few dollars. An alert on a few dollars is one nobody reads.

The region lock denies every region but `us-east-1` and the one the `region` variable names.
CloudFront certificates, Billing and CUR need `us-east-1`. Global services have no region, so
`scp.tf` excepts them by name.

## The CI role plans, and only a person applies

**A role that could apply would make the PR review advisory.** `lakeworks-github-plan` holds
nothing beyond `ReadOnlyAccess`, access to the state bucket so a plan can take the lock, and the
`sts:AssumeRole` grant below.

**Planning a member account is a second hop.** GitHub federates into `lakeworks-github-plan`, which
assumes a read-only role in `dev`. `ReadOnlyAccess` grants no `sts:AssumeRole`. So the role carries
an explicit grant onto `lakeworks-*-plan-role` in `dev`. Without it, every member-account plan fails
at the hop rather than at the plan. The grant is half the gate. A role in `dev` is reachable only
when its own trust policy names this one.

**The trust policy matches the subject's ids, not just its names.** GitHub's immutable subject
appends a numeric id to the owner and to the repository:
`repo:<owner>@<owner-id>/<repo>@<repo-id>:...`. A trust policy on the plain `owner/repo` form
matches nothing. The owner id is pinned. The repository id is wildcarded behind the `lakeworks-*`
and `terraform-aws-lakeworks-*` name prefixes, so a repo is trusted before anyone knows its id.

```bash
gh api repos/<owner>/<repo>/actions/oidc/customization/sub   # the subject prefix a token presents
```

**The OIDC thumbprint is read live, never pinned.** AWS validates GitHub's provider against its own
trusted root CAs. It ignores the thumbprint. A hardcoded fingerprint is a hardcoded expiry date
either way.

## `prevent_destroy` guards the organization and the state bucket, never the account

An organization can be deleted only after every member account has left it. Re-applying then
creates a different organization, which those accounts are not in. Losing the state bucket loses
every state kept in it.

The `dev` account carries `close_on_deletion = false`. Destroying it removes the account from the
organization and leaves it standalone. It can be invited back, so the mistake is recoverable.

## The `dev` account exists before anything can assume into it

A provider configuration cannot depend on a resource created in the same apply, because provider
configuration resolves at plan time. So `dev` is created here. Only a later apply can configure a
provider that assumes into it. That is inherent to Terraform, not a sequencing mistake to engineer
around.

That is why `lakeworks-platform-core` is a separate apply. It takes this apply's output as its
`dev_account_id` variable.

```bash
terraform output dev_account_id    # what platform-core takes as dev_account_id
```

## CI posts a plan on every pull request, and that plan is the review

`.github/workflows/plan.yml` runs `terraform plan` and posts it to the pull request. It assumes
`lakeworks-github-plan`, which this repo's own first apply creates. So it cannot run until bootstrap
has been applied once by hand. Every later repo has the role from day one.

It reads these repository variables, set once after the first apply. None is a secret. None belongs
in a tracked file, because an account id in a workflow is a permanent disclosure in a public repo.

```bash
gh variable set AWS_PLAN_ROLE_ARN     --body "$(terraform output -raw github_plan_role_arn)"
gh variable set TF_STATE_BUCKET       --body "$(terraform output -raw state_bucket)"
gh variable set MANAGEMENT_ACCOUNT_ID --body "$ACCOUNT"
gh variable set DEV_ACCOUNT_EMAIL     --body "<dev_account_email from terraform.tfvars>"
gh variable set ALERT_EMAIL           --body "<alert_email from terraform.tfvars>"
```

`.github/workflows/validate.yml` runs on pull requests and pushes to `main`, with no AWS
credentials. It initializes without a backend and runs the hooks in `.pre-commit-config.yaml` over
the change.
