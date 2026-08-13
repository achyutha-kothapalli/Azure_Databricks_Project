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

    pull_request {
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_approving_review_count   = 0
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      required_check {
        context = "Python, data, and workload contracts"
      }

      required_check {
        context = "Terraform formatting and validation"
      }
    }
  }
}

# Adopt the ruleset created during repository setup. Keeping the import in code
# prevents a new Terraform state from attempting to create a duplicate ruleset.
import {
  to = github_repository_ruleset.develop
  id = "Azure_Databricks_Project:20793393"
}
