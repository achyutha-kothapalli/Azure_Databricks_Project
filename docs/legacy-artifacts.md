# Legacy Proof-of-Concept Artifacts

Files under `Scripts/` describe the manually deployed proof of concept. They are migration inputs,
not the target production implementation.

| Artifact | Current role | Planned replacement |
|---|---|---|
| `Scripts/git.json` | Historical metadata from click-ops ingestion | Replaced in code by `config/datasets.json` and Terraform ADF artifacts |
| `Scripts/silver_layer.ipynb` | Historical interactive bronze-to-silver logic | Replaced in code by tested modules under `src/adventure_works`; Azure job verification pending |
| `Scripts/gold_layer.sql` | Historical manually executed Synapse views | Replaced by ordered, typed SQL under `synapse/sql`; live query verification pending |

## Metadata migration status

`config/datasets.json` is the canonical location used by the code-defined ADF pipeline. Repository
validation checks this manifest directly against the source files and expected row counts.
`Scripts/git.json` is no longer synchronized or consumed by the new pipeline. It remains temporarily
to document the original proof-of-concept implementation until the Azure ingestion run is verified.

Remove a legacy artifact only after its replacement passes the documented Azure validation checks
and no deployed workload depends on the legacy path.
