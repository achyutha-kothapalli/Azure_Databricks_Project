# Legacy Proof-of-Concept Artifacts

Files under `Scripts/` describe the manually deployed proof of concept. They are migration inputs,
not the target production implementation.

| Artifact | Current role | Planned replacement |
|---|---|---|
| `Scripts/git.json` | Metadata consumed by click-ops ingestion | `config/datasets.json` used by source-controlled ADF artifacts |
| `Scripts/silver_layer.ipynb` | Interactive bronze-to-silver logic | Tested Python package deployed with a Databricks Bundle |
| `Scripts/gold_layer.sql` | Manually executed Synapse views | Ordered, parameterized, idempotent SQL scripts |

## Temporary metadata duplication

`config/datasets.json` is the target canonical location, but `Scripts/git.json` remains until the ADF
pipeline is migrated and tested against the new path. `tools/validate_repository.py` requires both
files to be identical so the compatibility copy cannot drift silently.

Remove a legacy artifact only after its replacement passes the documented Azure validation checks
and no deployed workload depends on the legacy path.
