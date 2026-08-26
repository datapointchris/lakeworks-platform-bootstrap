output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "dev_account_id" {
  description = "Needed by every other repo's provider config. Read from SSM rather than remote state — remote state would give each pipeline read access to this whole file."
  value       = aws_organizations_account.dev.id
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "github_oidc_provider_arn" {
  description = "The OIDC provider every lakeworks CI role federates against."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_plan_role_arn" {
  description = "Assumed by GitHub Actions to plan. Cannot apply."
  value       = aws_iam_role.github_plan.arn
}
