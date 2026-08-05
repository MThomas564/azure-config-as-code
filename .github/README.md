# GitHub Actions Workflows

These workflows are the GitHub Actions equivalent of the Azure DevOps pipelines
in [`.pipelines/`](../.pipelines). Both sets of pipelines coexist — the ADO
pipelines are unchanged, so this addition is fully backwards compatible.

## Mapping

| Azure DevOps (`.pipelines/`) | GitHub Actions (`.github/`) |
|------------------------------|-----------------------------|
| `pr-validate.yaml` | `workflows/pr-validate.yml` |
| `deploy.yaml` | `workflows/deploy.yml` |
| `prepare-template.yaml` | `actions/prepare-config/action.yml` (composite) |
| `deploy-template.yaml` | `actions/appconfig-import/action.yml` (composite) |

## Behaviour parity

- **PR validation** runs on pull requests to `main` that touch `config/*.json`
  or `schema/*.schema.json`, validating each config file against
  `schema/config.schema.json` (same `Test-Json` logic as ADO).
- **Deploy** runs on push to `main`: it prepares/flattens the configs and
  publishes them as the `flattened-configs` artifact, performs a dry-run import,
  then publishes to Azure App Configuration. `az appconfig kv import` with
  `--profile appconfig/kvset --skip-features` mirrors
  `AzureAppConfigurationImport@10` (`FileContentProfile: appconfig/kvset`,
  `ExcludeFeatureFlags: true`).

## Required configuration

Set these under **Settings → Secrets and variables → Actions**:

- Variable `APP_CONFIG_ENDPOINT` — App Configuration endpoint URL
  (replaces the `{{APP CONFIG HERE}}` placeholder).
- Secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` — used by
  `azure/login` via OIDC (replaces the `{{AZURE SUBSCRIPTION HERE}}` service
  connection). The federated credential must trust this repository.

## Optional manual approval

The `deploy-dev` job targets the `dev` GitHub Environment. Add **required
reviewers** to that environment (**Settings → Environments → dev**) to gate the
publish step — the equivalent of the optional `ManualValidation@0` step in the
ADO `deploy-template.yaml`.
