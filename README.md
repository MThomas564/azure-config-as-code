# Azure App Configuration as Code Example

This repository demonstrates a pattern for managing [Azure App Configuration](https://learn.microsoft.com/en-gb/azure/azure-app-configuration/overview) using code and CI/CD pipelines. It is designed as a template that you can clone and adapt for your own environments to enable robust, auditable, and repeatable configuration management.

## Key Features

- **Configuration as Code:** Store your application configuration in version-controlled JSON files.
- **Flattening Complex Structures:** Automatically flattens complex JSON objects before publishing to Azure App Configuration, allowing you to use nested or complex objects in your source files.
- **Immutable Rollback:** Publishes the flattened configuration as a build artifact before deployment, providing an immutable rollback point for each release.
- **Dry Run & Approval:** Supports a dry run mode and optional manual approval step before publishing changes to Azure App Configuration.

**Pipeline-Driven:** Uses Azure Pipelines YAML for automation, including dry run, artefact publishing, and deployment.

## Pipeline Templates & JSON Schema Validation

This repository now uses pipeline templates and a JSON schema for robust configuration management:

- **Pipeline Templates:**
   - `.pipelines/prepare-template.yaml` validates your config files against the schema and converts them to a key-value format for Azure App Configuration.
   - `.pipelines/deploy-template.yaml` handles dry run, manual approval, and publishing to Azure App Configuration using parameterized steps.

- **JSON Schema Validation:**
   - The schema in `schema/config.schema.json` ensures your config files are valid and conform to expected structure and types before deployment.
   - Validation is performed automatically in the pipeline, and errors will block deployment until resolved.

### How to Use

1. Place your environment config files in `config/` (e.g., `dev.json`).
2. Update or extend the schema in `schema/config.schema.json` as needed for your application.
3. The pipeline will validate, flatten, and publish your configs using the templates provided.

See the pipeline YAML files and schema for more details and customization options.

## Repository Structure

- `config/` — Contains environment-specific configuration files (e.g., `dev.json`).
- `.pipelines/` — Contains pipeline YAML files and deployment templates.
- `README.md` — This documentation.

## How It Works

1. **Prepare & Flatten Config:**
   - The pipeline flattens all JSON config files in `config/`, converting nested objects into a flat key-value structure suitable for Azure App Configuration.
   - The flattened files are saved as `*.flattened.json` alongside the originals.

2. **Publish Artefact:**
   - The flattened config files are archived and published as a build artefact (`flattened-configs`).
   - This artefact serves as an immutable snapshot for rollback or audit purposes.

3. **Dry Run Import:**
   - The pipeline performs a dry run import to Azure App Configuration using the flattened config, validating changes without applying them.

4. **Manual Approval (Optional):**
   - If enabled, a manual approval step is inserted before actual publishing.

5. **Publish to Azure App Configuration:**
   - Upon approval, the pipeline publishes the flattened configuration to the specified Azure App Configuration instance.


## Supported Data Types & Handling

Your configuration schema supports several data types, each handled specifically during conversion to Azure App Configuration KVSet format:

- **string**: Stored as plain text (`content_type: text/plain`).
- **json**: Stored as a compressed JSON string (`content_type: application/json`).
- **jsonarray**: Each array item is split into individual keys with an index (e.g., `key:0`, `key:1`), stored as compressed JSON (`content_type: application/json`).
- **featureflag**: Stored in Azure App Configuration feature flag format (`content_type: application/vnd.microsoft.appconfig.ff+json;charset=utf-8`). Keys are prefixed with `.appconfig.featureflag/` if not already present.
- **keyvault**: Stored as a Key Vault reference (`content_type: application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8`).
- **default/other types**: Stored as plain text.

Each item can also include optional `label` and `tags` properties, which are preserved in the output.

See `schema/config.schema.json` for the full schema definition and `scripts/convert-to-kvset.ps1` for implementation details.
## Example Configuration (`config/dev.json`)

```json
{
  "AppName": "MyApplication",
  "Environment": "Development",
  "FinBuckle:MultiTenant:Stores:ConfigurationStore": {
    "Tenants": [
      { "Id": "tenant1", "Name": "Tenant One", "EnableLookup": true },
      { "Id": "tenant2", "Name": "Tenant Two", "EnableLookup": false }
    ]
  }
}
```

## Pipeline Overview

- **Pipeline File:** `.pipelines/deploy.yaml`
- **Template:** `.pipelines/deploy-template.yaml`
- **Key Steps:**
  - Flatten config files
   - Archive and publish as artefact
  - Dry run import to Azure App Configuration
  - (Optional) Manual approval
  - Publish to Azure App Configuration

## Customisation

- Add or modify config files in the `config/` directory for your environments.
- Adjust the pipeline YAML to fit your Azure environment, subscriptions, and approval requirements.
- The flattening logic can be extended to support additional data types or structures as needed.

## Getting Started

1. **Clone this repository:**
   ```powershell
   git clone <this-repo-url>
   ```
2. **Update configuration files** in `config/` for your application and environments.
3. **Set up your Azure Pipeline** using the provided YAML files. You will need to update the following placeholders in `.pipelines/deploy.yaml`:
   - `{{POOL OPTIONS HERE}}`: Specify your Azure DevOps agent pool (e.g., `name: 'Azure Pipelines'` or your custom pool).
   - `{{APP CONFIG HERE}}`: The endpoint URL of your Azure App Configuration instance (e.g., `https://<your-app-config-name>.azconfig.io`).
   - `{{AZURE SUBSCRIPTION HERE}}`: The name or ID of the Azure subscription service connection to use for deployment.
   - You may also need to update the `environment`, `configFile`, and `flattenedFile` parameters if you add more environments or change file names.
4. **Run the pipeline** to validate, approve, and publish your configuration.

## Licence

This repository is provided as an example. Adapt and use as needed for your organisation.

---

### Required User Configuration

Before running the pipeline, ensure you have set the following in `.pipelines/deploy.yaml`:

- **Agent Pool:** Replace `{{POOL OPTIONS HERE}}` with your Azure DevOps agent pool configuration.
- **App Configuration Endpoint:** Replace `{{APP CONFIG HERE}}` with your Azure App Configuration endpoint.
- **Azure Subscription:** Replace `{{AZURE SUBSCRIPTION HERE}}` with your Azure subscription service connection name or ID.

If you add new environments or configuration files, update the relevant parameters in the pipeline accordingly.
