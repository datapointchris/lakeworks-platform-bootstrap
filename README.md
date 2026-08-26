# lakeworks-platform-bootstrap

The things that must exist before Terraform can manage anything else: the AWS Organization, the
`dev` member account, the state bucket, the region-lock SCP, the GitHub OIDC provider, the plan-only
CI role and the billing guardrails.

**Run by hand, a handful of times ever.** Everything else in lakeworks is applied against `dev` by
`lakeworks-platform-core` and the pipeline repos.

## Dedicated accounts, not a promoted one

The organization is standalone. No pre-existing account is promoted into it.

```text
  management
    billing · Organizations · state bucket
    OIDC · budgets · Identity Center
    NO workload
      ├── dev
      └── prod   (later, additively)
```

**Why a dedicated empty management account**: **service control policies do not apply to the
management account.** Anything living there is permanently outside every guardrail, including the
region lock. An account holding real infrastructure is exactly what must not be the org root.

The secondary benefit is that the platform owns its own GitHub OIDC provider. AWS permits one per
URL per account, so a shared account forces one Terraform state to reference what another manages —
whichever applies last wins, and the loser's next plan shows a phantom change.

## Why this is a separate repo from platform-core

Not tidiness — CI credentials.

`lakeworks-platform-core` runs in GitHub Actions. If account creation lived in the same root module,
the CI role would need `organizations:CreateAccount`, and a compromised workflow could create AWS
accounts on the bill. Split, and the CI role never holds Organizations permissions at all.

The boundary case worth knowing: **the OIDC provider is bootstrap**, because CI cannot run anything
until it exists.

## One-time setup

Steps 1-5 are yours; nothing can automate them, because a brand-new AWS account has only a root user
and no credential to act with.

**1 · Three Fastmail aliases.** Two now, one later for prod. Real aliases rather than plus-addressing
— a root email is load-bearing for the life of the account, and Fastmail includes 600+ aliases on
every plan including Basic.

```text
  aws-lakeworks@…         the management account root
  aws-lakeworks-dev@…     the dev member account
  aws-lakeworks-prod@…    later
```

**2 · Sign up the management account.**

> ⚠️ **Choose the Paid plan, not the Free plan.** AWS reworked the free tier in July 2025. A Free
> plan account gives $100 in credits plus up to $100 more for onboarding tasks — and then **closes
> automatically** at six months or when the credits run out, whichever comes first. Resources shut
> down and you get 90 days to upgrade before deletion. That is not a plan to put a platform on.
>
> Member accounts created through Organizations inherit consolidated billing and never see this
> choice, so it is made exactly once.

**3 · Turn on MFA for the root user, then stop using root.**

**4 · Create the Terraform credential.** As root, one IAM user with `AdministratorAccess` and MFA
enabled, then an access key into a named profile:

```bash
aws configure --profile lakeworks
export AWS_PROFILE=lakeworks
aws sts get-caller-identity          # confirm the account id before going further
```

> A long-lived admin access key is the weakest part of this setup and it is deliberate: something
> has to hold the first credential. **Replacing it with IAM Identity Center is follow-up work**, and
> until that lands this key is the thing worth guarding.

**5 · Create the state bucket.** Terraform needs somewhere to keep state before it can create
anything, so this one bucket is made by hand and adopted on the first apply.

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lakeworks-tfstate-${ACCOUNT}"

aws s3api create-bucket --bucket "$BUCKET" --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
```

**6 · Run it.**

```bash
cp terraform.tfvars.example terraform.tfvars    # fill in ids and emails
terraform init -backend-config="bucket=lakeworks-tfstate-${ACCOUNT}"
terraform plan -out=bootstrap.tfplan            # review this
terraform apply bootstrap.tfplan
```

`providers.tf` carries a `check` block that refuses to run if the credentials name a different
account than `management_account_id`. Creating an organization in the wrong account is not something
to discover afterwards.

## What it creates

```text
MANAGEMENT                                   DEV (created here)
  Organization, feature_set = ALL              region-lock SCP attached
  SCP: lakeworks-region-lock                   OrganizationAccountAccessRole
  S3 lakeworks-tfstate-<account>               (everything else is platform-core's)
  OIDC provider, owned outright
  IAM lakeworks-github-plan  ← plan only
  Budgets: actual $20, forecast $40
  Cost Anomaly Detection, $10 absolute
  SNS lakeworks-billing-alerts
```

Guardrails are in the *first* apply on purpose. Nothing should be able to spend before the alarm
that watches spending exists, and billing is management-level — which is why budgets live here
rather than with the rest of the observability work in `lakeworks-platform-core`.

The budget carries **no cost filter**. The account boundary separates spend, and does it more
accurately than a tag filter, because it catches resources nobody remembered to tag.

## Four decisions encoded here

**The CI role can plan and cannot apply.** Applies are a human act. A role that could apply would
make the PR review advisory rather than load-bearing.

**The state bucket is adopted, not created.** Four `import` blocks, which stay in the file after the
first apply as the record of how the bucket got here.

**`prevent_destroy` guards the organization, not the account.** Removing an organization orphans
every member account and cannot be undone by re-applying. Removing the *account* resource only drops
it from state — `close_on_deletion = false` — which is recoverable.

**The OIDC thumbprint is read live, never pinned.** AWS no longer verifies it for well-known
providers, but a hardcoded fingerprint is a hardcoded expiry date either way.

## The two-stage problem

A provider configuration cannot depend on a resource created in the same apply, because provider
config resolves at plan time. So the `dev` account is created here, and only a **later** apply can
configure a provider that assumes into it.

That is inherent to Terraform, not a design flaw, and it is why `lakeworks-platform-core` is a
separate apply that reads the account id from SSM rather than doing everything at once.

## Plan on PR

Three repository variables have to be set once, after the first apply. None is a secret, and none
belongs in a tracked file — an account id in a workflow is a permanent disclosure in a public repo.

```bash
gh variable set AWS_PLAN_ROLE_ARN  --body "arn:aws:iam::<management-account>:role/lakeworks-github-plan"
gh variable set DEV_ACCOUNT_EMAIL  --body "<the dev account email>"
gh variable set ALERT_EMAIL        --body "<where alerts land>"
```

`.github/workflows/plan.yml` posts the plan to the pull request. It assumes the
`lakeworks-github-plan` role that this repo's own first apply creates, so it cannot run until
bootstrap has been applied once by hand. Every later repo has the role from day one.
