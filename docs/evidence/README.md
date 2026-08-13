# Portfolio Evidence

This directory contains only redacted evidence suitable for a public repository. Raw Azure output
belongs in the ignored `docs/evidence/private` directory.

## Evidence rules

Do not publish:

- Subscription, tenant, resource, workspace, cluster, pipeline, or run identifiers
- User names, email addresses, application IDs, or object IDs
- Tokens, credentials, state contents, backend names, or storage URLs
- Terminal output that includes local paths or account context
- Screenshots with portal navigation containing identifying values

Redact identifiers rather than replacing failed or pending evidence with a claim. Mark unexecuted
checks as pending.

## Recommended portfolio set

Keep the public set small:

1. One architecture diagram from the README.
2. One successful CI run showing both required jobs.
3. A redacted Terraform plan summary and empty follow-up plan.
4. ADF ingestion summary for ten datasets and 77,259 source rows.
5. Databricks two-run comparison showing stable silver counts.
6. Synapse verification showing eight base views and two semantic views.
7. Databricks cleanup confirmation showing no workspace, managed group, or NAT Gateway.

Use `verification-summary.example.md` as the structure for the final evidence narrative.
