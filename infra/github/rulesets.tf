resource "github_repository_ruleset" "develop" {
  name        = "develop_protect"
  repository  = var.github_repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/heads/develop"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true
  }
}

# Adopt the ruleset created during repository setup. Keeping the import in code
# prevents a new Terraform state from attempting to create a duplicate ruleset.
import {
  to = github_repository_ruleset.develop
  id = "Azure_Databricks_Project:20793393"
}
