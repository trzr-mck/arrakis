terraform {
  required_version = ">= 1.6.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.6"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state — uncomment and fill in before running in anything but a
  # throwaway sandbox.
  #
  # SECURITY NOTE: Terraform state for this module contains security-critical
  # configuration (ruleset definitions, bypass-actor wiring, team membership).
  # It does NOT contain the App private key (that is only ever passed in via
  # TF_VAR_iac_app_pem), but tampering with state is equivalent to tampering
  # with the controls themselves. The bucket must be encrypted (SSE-KMS),
  # versioned, and access-restricted to the IaC pipeline role only.
  # ---------------------------------------------------------------------------
  # backend "s3" {
  #   bucket         = "REPLACE-ME-tfstate-bucket"
  #   key            = "github-four-eyes-poc/terraform.tfstate"
  #   region         = "REPLACE-ME"
  #   dynamodb_table = "REPLACE-ME-tfstate-lock"
  #   encrypt        = true
  # }
}

locals {
  # PEM resolution: prefer the in-memory value (prod: from secrets manager via
  # TF_VAR_iac_app_pem); fall back to reading a local file (test only).
  # file() returns the file *contents*, which is what app_auth.pem_file wants.
  iac_app_pem = var.iac_app_pem != "" ? var.iac_app_pem : file(var.iac_app_pem_file)
}

# Authenticate as a GitHub App installation — never a PAT.
# The App needs: repo admin, org admin, members read/write, actions read/write.
provider "github" {
  owner = var.org_name

  app_auth {
    id              = var.iac_app_id
    installation_id = var.iac_app_installation_id
    pem_file        = local.iac_app_pem
  }
}
