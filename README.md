 # Azure App Configuration as Code Example

  This repository demonstrates a pattern for managing [Azure App Configuration](https://learn.microsoft.com/en-gb/azure/azure-app-configuration/overview) using code and CI/CD pipelines. It is designed as a
  template that you can clone and adapt for your own environments to enable robust, auditable, and repeatable configuration management.

  ## Key Features

  - **Configuration as Code:** Store your application configuration in version-controlled JSON files.
  - **KVSet Conversion:** Converts your typed, human-editable config files into Azure App Configuration KVSet format (proper key-value pairs) ready for import. Complex JSON objects and arrays are flattened into
  `:`-delimited keys, and arrays support a configurable `flattenDepth` to break large nested arrays down further so each value stays within Azure App Configuration's per-key size limit.
  - **Immutable Rollback:** Publishes the generated KVSet files as a build artifact before deployment, providing an immutable rollback point for each release.
  - **Dry Run & Approval:** Supports a dry run mode and optional manual approval step before publishing changes to Azure App Configuration.

  **Pipeline-Driven:** Uses Azure Pipelines YAML for automation, including dry run, artefact publishing, and deployment.

  ## Pipeline Templates & JSON Schema Validation

  This repository now uses pipeline templates and a JSON schema for robust configuration management:

  - **Pipeline Templates:**
     - `.pipelines/prepare-template.yaml` validates your config files against the schema and converts them to Azure App Configuration KVSet format.
     - `.pipelines/deploy-template.yaml` handles dry run, manual approval, and publishing to Azure App Configuration using parameterized steps.

  - **JSON Schema Validation:**
     - The schema in `schema/config.schema.json` ensures your config files are valid and conform to expected structure and types before deployment.
     - Validation is performed automatically in the pipeline, and errors will block deployment until resolved.

  ### How to Use

  1. Place your environment config files in `config/` (e.g., `dev.json`).
  2. Update or extend the schema in `schema/config.schema.json` as needed for your application.
  3. The pipeline will validate, convert, and publish your configs using the templates provided.

  See the pipeline YAML files and schema for more details and customization options.

  ## Repository Structure

  - `config/` — Contains environment-specific configuration files (e.g., `dev.json`). Generated KVSet files (`*.kv.json`) are written here during the pipeline run.
  - `.pipelines/` — Contains pipeline YAML files and deployment templates.
  - `scripts/` — Contains `convert-to-kvset.ps1`, which converts a typed config file into KVSet format.
  - `schema/` — Contains the JSON schema used to validate config files.
  - `README.md` — This documentation.

  ## How It Works

  1. **Prepare & Convert Config:**
     - The pipeline validates every JSON config file in `config/` against the schema, then converts each one into Azure App Configuration KVSet format, flattening nested objects and arrays into `:`-delimited
  key-value pairs.
     - The converted files are saved as `*.kv.json` alongside the originals (e.g. `dev.json` produces `dev.kv.json`).

  2. **Publish Artifact:**
     - The generated `*.kv.json` files are archived and published as a build artifact (`flattened-configs`).
     - This artifact serves as an immutable snapshot for rollback or audit purposes.

  3. **Dry Run Import:**
     - The pipeline performs a dry run import to Azure App Configuration using the generated KVSet files, validating changes without applying them.

  4. **Manual Approval (Optional):**
     - If enabled, a manual approval step is inserted before actual publishing.

  5. **Publish to Azure App Configuration:**
     - Upon approval, the pipeline publishes the KVSet configuration to the specified Azure App Configuration instance.


  ## Supported Data Types & Handling
  Your configuration schema supports several data types, each handled specifically during conversion to Azure App Configuration KVSet format:

  - **string**: Stored as plain text (`content_type: text/plain`).
  - **json**: Stored as a compressed JSON string (`content_type: application/json`).
  - **jsonarray**: Each array element is split into its own indexed key (e.g. `key:0`, `key:1`), stored as compressed JSON (`content_type: application/json`). Set the optional `flattenDepth` property (integer,
  default `0`) to also split nested arrays *inside* each element into their own indexed keys, up to `flattenDepth` levels deep — useful when a single element would otherwise exceed the App Configuration value size
  limit.
  - **featureflag**: Stored in Azure App Configuration feature flag format (`content_type: application/vnd.microsoft.appconfig.ff+json;charset=utf-8`). Keys are prefixed with `.appconfig.featureflag/` if not
  already present.
  - **keyvault**: Stored as a Key Vault reference (`content_type: application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8`).
  - **default/other types**: Stored as plain text.

  Each item can also include optional `label` and `tags` properties, which are preserved in the output.

  See `schema/config.schema.json` for the full schema definition and `scripts/convert-to-kvset.ps1` for implementation details.

  ## Configuration File Structure

  All configuration files live in the `config/` directory and must conform to the JSON schema in `schema/config.schema.json`. Each file contains an `items` array where each entry has a `key`, `type`, `value`, and
  optionally a `label` and `tags`.

  The `type` field controls how the value is handled by the pipeline:

  | Type | Description |
  |------|-------------|
  | `string` | A plain string value |
  | `json` | A JSON object — stored as a serialised JSON string in App Config |
  | `jsonarray` | A JSON array — each element published as its own indexed key (`key:0`, `key:1`, …); supports an optional `flattenDepth` to split nested arrays further |
  | `featureflag` | An Azure App Configuration feature flag |
  | `keyvault` | A Key Vault reference |

  ### String example

  ```json
  {
    "items": [
      {                                                                                                           
        "key": "MyApp:Settings:ApiUrl",
        "type": "string",
        "value": "https://api.example.com",
        "label": "production"
      }
    ]
  }
  ```

  ### JSON example                                                                                                                                                                                       

  ```json
  {                                                                                                               
    "items": [                                                                                                                                                                                           
      {
        "key": "MyApp:Settings:Tenants",
        "type": "json",
        "value": {
          "Tenants": [
            { "Id": "tenant1", "Name": "Tenant One" },
            { "Id": "tenant2", "Name": "Tenant Two" }
          ]
        }
      }
    ]
  }
  ```
                                                                                                                  
  ### JSON array example                                                                                                                                                                                 

  Use `jsonarray` when you want each element of an array published as its own key
  (`key:0`, `key:1`, …) instead of one serialised blob, so consumers can bind them
  back into a collection via the `:` separator.

  ```json
  {
    "items": [
      {
        "key": "MyApp:Clusters",
        "type": "jsonarray",
        "value": [
          { "Name": "primary", "Region": "uksouth" },
          { "Name": "secondary", "Region": "ukwest" }
        ]
      }
    ]
  }
  ```

  Produces (`content_type: application/json`):

  | Key | Value |
  |-----|-------|
  | `MyApp:Clusters:0` | `{"Name":"primary","Region":"uksouth"}` |
  | `MyApp:Clusters:1` | `{"Name":"secondary","Region":"ukwest"}` |

  #### Controlling flatten depth

  Large or deeply-nested elements can still exceed Azure App Configuration's
  per-value size limit. Set the optional `flattenDepth` property (integer, default
  `0`) to break nested arrays *within* each element out into their own indexed keys:

  - `0` (default) — each top-level element is written whole, as one compressed JSON value.
  - `1` — additionally split any array-valued property one level down into `:0`, `:1`, … keys.
  - `n` — repeat for up to `n` levels of nested arrays.

  Scalar properties always stay grouped with their parent object; only array-valued
  properties are split out. Every resulting key is stored as compressed JSON
  (`content_type: application/json`).

  ```json
  {
    "items": [
      {
        "key": "MyApp:Clusters",
        "type": "jsonarray",
        "flattenDepth": 1,
        "value": [
          {
            "Name": "primary",
            "Region": "uksouth",
            "Nodes": [
              { "Host": "node-a", "Port": 8080 },
              { "Host": "node-b", "Port": 8080 }
            ]
          }
        ]
      }
    ]
  }                                                                                                                                                                                                      
  ```
  
  Produces:                                                                                                       
                                                                                                                                                                                                         
  | Key | Value |
  |-----|-------|
  | `MyApp:Clusters:0` | `{"Name":"primary","Region":"uksouth"}` |
  | `MyApp:Clusters:0:Nodes:0` | `{"Host":"node-a","Port":8080}` |
  | `MyApp:Clusters:0:Nodes:1` | `{"Host":"node-b","Port":8080}` |

  With `flattenDepth` omitted (or `0`), the same input produces a single key
  `MyApp:Clusters:0` containing the whole element, `Nodes` array included.

  ### Feature flag example

  ```json
  {                                                                                                               
    "items": [                                                                                                                                                                                           
      {
        "key": "MyFeature",
        "type": "featureflag",
        "value": {
          "id": "MyFeature",
          "enabled": true,
          "conditions": {
            "client_filters": []
          }
        }
      }
    ]
  }                                                                                                               
  ```                                                                                                                                                                                                    

  ### Key Vault reference example

  ```json
  {
    "items": [                                                                                                                                                                                           
      {
        "key": "MyApp:Secrets:ApiKey",
        "type": "keyvault",                                                                                       
        "value": {                                                                                                                                                                                       
          "uri": "https://my-vault.vault.azure.net/secrets/my-api-key"
        }
      }
    ]
  }
  ```
                                                                                                                  
  ## Pipeline Overview                                                                                                                                                                                   

  - **Pipeline File:** `.pipelines/deploy.yaml`
  - **Template:** `.pipelines/deploy-template.yaml`
  - **Key Steps:**
    - Convert config files to KVSet format
    - Convert config files to KVSet format
     - Archive and publish as artefact
    - Dry run import to Azure App Configuration
    - (Optional) Manual approval
    - Publish to Azure App Configuration
  
  ## Customisation
  
  - Add or modify config files in the `config/` directory for your environments.
  - Adjust the pipeline YAML to fit your Azure environment, subscriptions, and approval requirements.
  - The conversion logic (`scripts/convert-to-kvset.ps1`) can be extended to support additional data types or structures as needed. Array flattening depth is controlled per-item via `flattenDepth`.
  
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
     - You may also need to update the `environment`, `configFile`, and `flattenedFile` parameters (the latter points at the generated `*.kv.json`) if you add more environments or change file names.
  4. **Run the pipeline** to validate, approve, and publish your configuration.
  
  ## Licence
  
  Licensed under the MIT Licence. See [LICENSE](LICENSE) for details.
  
  ---
  
  ### Required User Configuration
  
  Before running the pipeline, ensure you have set the following in `.pipelines/deploy.yaml`:
  
  - **Agent Pool:** Replace `{{POOL OPTIONS HERE}}` with your Azure DevOps agent pool configuration.
  - **App Configuration Endpoint:** Replace `{{APP CONFIG HERE}}` with your Azure App Configuration endpoint.
  - **Azure Subscription:** Replace `{{AZURE SUBSCRIPTION HERE}}` with your Azure subscription service connection name or ID.
  
  If you add new environments or configuration files, update the relevant parameters in the pipeline accordingly.
  
  ---
  
  Optional pipeline renames for full consistency (so nothing says "flattened"):
  
  - .pipelines/prepare-template.yaml → ArtifactName: 'flattened-configs' becomes ArtifactName: 'kvset-configs'
  - .pipelines/deploy.yaml → artifactName: 'flattened-configs' and downloadPath reference become kvset-configs; rename the flattenedFile: parameter to kvSetFile:
  - .pipelines/deploy-template.yaml → rename the flattenedFile parameter to kvSetFile (3 usages)
