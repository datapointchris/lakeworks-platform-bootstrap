terraform {
  # Partial config: the bucket name carries the account id, which does not exist until the
  # management account is created. Supplied at init time — see the README.
  #
  #   terraform init -backend-config="bucket=lakeworks-tfstate-<management-account-id>"
  backend "s3" {
    key          = "management/bootstrap/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true # S3 native locking; no DynamoDB table
  }
}
