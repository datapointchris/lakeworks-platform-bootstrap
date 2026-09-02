# CLAUDE.md

Guidance for Claude Code working in this repository.

Read the README first. It carries why the organization is standalone, why this is a separate repo
from `lakeworks-platform-core`, and the one-time setup steps that cannot be automated.

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

The management account holds billing, Organizations, the state bucket, the OIDC provider and the
budgets. **No workload, ever.** Service control policies do not apply to the management account, so
anything placed here sits permanently outside every guardrail including the region lock. Adding a
bucket or a role "just for now" is what makes the guardrails decorative.

Workload infrastructure belongs in a member account, applied by `lakeworks-platform-core` or a
pipeline repo.

## Two structural constraints that look like bugs

**A provider config cannot depend on a resource created in the same apply.** The member account is
created here, and only a later apply can assume into it. This is inherent, not a sequencing mistake
to engineer around.

**The state bucket holds the state that manages the state bucket.** It is created once by hand with
a single CLI call and adopted with `import` blocks. Do not try to make the first apply create it.

## Permissions boundaries worth keeping

The CI role is plan-capable, never apply-capable. Account creation lives here precisely so the CI
role never holds `organizations:CreateAccount` — a compromised workflow must not be able to create
accounts on the bill. Do not widen that role to make a workflow succeed; the workflow is supposed
to stop at plan.

`ReadOnlyAccess` grants no `sts:AssumeRole`. A read-only role that must hop into a member account
needs the grant added explicitly, and its absence presents as a confusing denial on the second hop
rather than on the first.

## OIDC subjects carry ids, not just names

GitHub's subject claim appends a numeric owner id and repository id to the names they follow, so a
trust policy matching on the plain `owner/repo` form matches nothing. Match the id-bearing form.
The repository's own OIDC customization endpoint returns the literal prefix without exchanging a
token, which is the cheapest way to confirm the shape.
