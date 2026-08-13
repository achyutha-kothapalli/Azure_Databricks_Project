# Architecture Decisions

These decisions guide productionization of the original Azure proof of concept. A decision can be
revised, but the change and its consequences should be recorded in the implementing pull request.

## AD-001: Preserve the working proof of concept during migration

**Status:** Accepted

The existing notebook, SQL script, and `Scripts/git.json` remain available while deployable
replacements are developed and verified. Removing or redirecting an artifact before its replacement
works in Azure could break the current demonstration.

## AD-002: Terraform manages Azure infrastructure

**Status:** Accepted

Terraform will manage resource groups, ADLS Gen2, Azure Data Factory, Azure Databricks, Synapse,
identities, role assignments, and diagnostics. Shared modules will be called by thin environment
roots to reduce configuration drift.

## AD-003: Databricks workloads use Declarative Automation Bundles

**Status:** Accepted

Terraform will provision privileged Azure and workspace infrastructure. A Databricks Bundle will
package and deploy application code, job configuration, parameters, and environment targets.

## AD-004: ADF remains the ingestion orchestrator

**Status:** Accepted for this project

ADF remains responsible for metadata-driven GitHub-to-bronze ingestion. Databricks could ingest
these files directly, but retaining ADF demonstrates connector-based ingestion and separates
orchestration from transformation.

## AD-005: Silver storage migrates from Parquet to Delta

**Status:** Accepted and implemented

The current Parquet append pattern is unsafe to rerun. Delta will support schema enforcement and
idempotent overwrite or merge behavior. Migration will follow transformation unit tests.

## AD-006: Synapse serverless remains the serving layer

**Status:** Accepted for this project

Synapse serverless SQL continues to expose gold views. This provides a T-SQL consumption surface
over lake data. Databricks SQL remains a valid alternative for a larger client workload.

## AD-007: Unity Catalog is out of scope

**Status:** Accepted

Unity Catalog is not used in the current environment and will not be introduced during this scoped
productionization. Its governance implications remain documented as a limitation.

## AD-008: Prefer identity-based authentication

**Status:** Accepted and implemented

Managed identities and Azure RBAC should replace storage keys and embedded client secrets wherever
supported. CI/CD should use workload identity federation rather than stored client secrets.

## AD-009: Keep silver Delta compatible with Synapse serverless SQL

**Status:** Accepted

Synapse serverless SQL supports the Delta reader version 1 feature set. Silver tables therefore use
reader version 1 and writer version 2, disable deletion vectors and column mapping, and retain classic
checkpoints. The pipeline rejects an existing target that crosses this boundary. If newer Delta
features become necessary, the serving engine must change or receive a separate compatible
projection.

## AD-010: Synapse uses workspace identity and typed views

**Status:** Accepted

The Synapse workspace managed identity reads the silver filesystem through a database-scoped
credential. Gold views declare every source column and SQL type, use UTF-8 collation, and expose a
least-privilege schema to an external reader principal. Storage keys and SAS tokens are not used.

## AD-011: Separate credential-free CI from approved Azure deployment

**Status:** Accepted

Pull-request validation receives read-only repository permission and cannot request an Azure token.
Development deployment is manually dispatched, uses GitHub OIDC, produces a plan before a protected
apply job, and never deploys Databricks. Test and production remain configuration-only targets.

## AD-012: Keep raw operational evidence private

**Status:** Accepted

Raw Azure output, identifiers, and run logs remain under an ignored private evidence directory. The
public portfolio contains only redacted summaries and screenshots. Pending live verification is
reported explicitly rather than represented by synthetic evidence.
