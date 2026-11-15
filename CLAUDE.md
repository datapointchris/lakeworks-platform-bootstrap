# lakeworks-platform-bootstrap

The README carries why the organization is standalone, why this is a separate repo from
`lakeworks-platform-core`, and the one-time setup steps that cannot be automated.

## This repo is applied by hand

Everything here runs a handful of times ever. Automation plans; a person applies. Do not add a
workflow that applies, do not reach for `terraform apply` to unblock something, and do not treat a
clean plan as permission to run one.

`terraform plan` is the right way to answer "is this converged". It needs credentials in the
management account and a `-backend-config` for the bucket, both described in the README.

## The backend is partial on purpose

The state bucket name carries the management account id, which does not exist until the account
does. So the bucket is supplied at init rather than written into `backend.tf`. Any instruction that
says to hardcode it is wrong.

`terraform.tfvars` is gitignored. `terraform.tfvars.example` is the tracked copy — keep the two in
step when adding a variable.

## What must never move into this account

**No workload, ever, not even "just for now".** Workload infrastructure belongs in a member account,
applied by `lakeworks-platform-core` or a pipeline repo. The README's "The management account holds
no workload, because no SCP reaches it" says why.

## Two structural constraints that look like bugs

**Do not make one apply create `dev` and assume into it.** The README's "The `dev` account exists
before anything can assume into it" says why Terraform cannot.

**The state bucket holds the state that manages the state bucket.** It is created once by hand with
the `aws s3api` calls in the README's first run, and adopted with `import` blocks. Do not try to
make the first apply create it.

## Permissions boundaries worth keeping

The CI role is plan-capable, never apply-capable. Account creation lives here precisely so the CI
role never holds `organizations:CreateAccount` — a compromised workflow must not be able to create
accounts on the bill. Do not widen that role to make a workflow succeed; the workflow is supposed
to stop at plan.

Keep the plan role's explicit `sts:AssumeRole` grant, and match trust policies on GitHub's
id-bearing OIDC subject, never the plain `owner/repo` form. The README's "The CI role plans, and
only a person applies" gives the reason for each and the command that prints a repo's subject prefix.
