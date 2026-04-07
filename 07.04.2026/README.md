# Azure Deployment Runbook — E-commerce (Terraform + GitHub Actions)

This repository contains infrastructure-as-code (Terraform) and CI/CD workflows (GitHub Actions) to deploy a Node.js e-commerce application to Azure.

## Architecture
- Environments: **staging** and **production**
- Region: **West Europe** (`westeurope`)
- Compute: Azure App Service (Linux)
  - Frontend Web App (Node.js)
  - REST API Web App (Node.js)
- Data:
  - Azure SQL Database (products + orders)
  - Azure Storage Account (Blob) for product images
- Secrets:
  - Azure Key Vault (secrets referenced by App Service)

Diagrams:
- PlantUML: `docs/ecomm-azure-architecture.puml`
- PNG: `docs/ecomm-azure-architecture.png`

## Repo contents
- Terraform:
  - `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`
- CI/CD:
  - `.github/workflows/deploy.yml`
  - `.github/workflows/destroy.yml`
- Sample app placeholders (optional):
  - `src/frontend`
  - `src/api`

## Important security notes
1) **Secrets in Terraform state**
   - The SQL admin password is stored in Key Vault, but Terraform also must know it to configure Azure SQL and to create the secret.
   - Therefore, the secret value will exist in Terraform state.
   - Mitigation: store state in an Azure Storage account with strict RBAC, private access, and auditing.

2) **Storage shared keys are disabled**
   - The Storage Account is configured with shared keys disabled.
   - Your API should use **Managed Identity + Azure RBAC** and the Azure SDK to access blobs.

3) **Key Vault access is RBAC-based**
   - Key Vault is configured with RBAC authorization enabled.
   - Web Apps are assigned the `Key Vault Secrets User` role.

## Prerequisites
### Local (optional)
- Terraform >= 1.6
- Azure CLI (`az`)

### Azure
- An Azure subscription where you can create:
  - Resource groups, App Service, Storage, Key Vault, SQL
  - Role assignments (RBAC)

### GitHub
- Ability to create GitHub Environments and configure secrets
- Ability to create an Entra app registration / service principal with federated credentials (OIDC)

## 1) Configure Terraform remote state (recommended)
Terraform is configured for an `azurerm` backend (remote state). Create one shared state store (one-time):

```powershell
# Choose a global-ish name; must be unique.
$stateRg = "rg-tfstate"
$stateLocation = "westeurope"
$stateSa = "tfs" + (Get-Random -Maximum 999999).ToString("000000") + "weu"
$stateContainer = "tfstate"

az group create --name $stateRg --location $stateLocation
az storage account create --name $stateSa --resource-group $stateRg --location $stateLocation --sku Standard_LRS --kind StorageV2 --https-only true
az storage container create --name $stateContainer --account-name $stateSa

Write-Host "TFSTATE_RESOURCE_GROUP=$stateRg"
Write-Host "TFSTATE_STORAGE_ACCOUNT=$stateSa"
Write-Host "TFSTATE_CONTAINER=$stateContainer"
```

Lock down the state storage account (recommended): private endpoints / firewall, limited RBAC, and consider versioning + soft delete.

## 2) Create Entra App / OIDC for GitHub Actions
Your workflows use `azure/login@v2` with OIDC.

High-level steps:
1) Create an Entra app registration (service principal)
2) Create a federated credential for your GitHub repo (and optionally for environments)
3) Grant the service principal required RBAC on the subscription or target resource groups

You will need these values for GitHub secrets:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

RBAC needed (minimum practical baseline):
- At subscription scope (simplest): `Contributor` + `User Access Administrator` (to create role assignments)
  - If you want least privilege, scope to specific resource groups and pre-create RBAC assignments, but Terraform still needs permissions to create role assignments.

## 3) Configure GitHub Environments and Secrets
Create GitHub Environments:
- `staging`
- `production` (configure required reviewers for approvals)

Set these secrets (either at repo level, or per-environment where appropriate):

Azure auth:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Terraform backend:
- `TFSTATE_RESOURCE_GROUP`
- `TFSTATE_STORAGE_ACCOUNT`
- `TFSTATE_CONTAINER`

Application/database:
- `SQL_ADMIN_PASSWORD`
  - Recommended: set different passwords for `staging` vs `production` using environment-scoped secrets.

### Checklist (exact names used by workflows)
GitHub Environments (Settings → Environments):
- `staging`
- `production` (recommended: require reviewers)

GitHub Secrets (Settings → Secrets and variables → Actions):

**Repo-level secrets (shared across staging/production)**
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TFSTATE_RESOURCE_GROUP`
- `TFSTATE_STORAGE_ACCOUNT`
- `TFSTATE_CONTAINER`

**Environment secrets (recommended: set separately for each environment)**
- `staging` environment:
  - `SQL_ADMIN_PASSWORD`
- `production` environment:
  - `SQL_ADMIN_PASSWORD`

Notes:
- The workflows reference these names exactly; changing them requires editing `.github/workflows/deploy.yml` and `.github/workflows/destroy.yml`.
- If you store `SQL_ADMIN_PASSWORD` at repo-level instead of environment-scoped, both staging and production will share the same value.

## 4) Deploy using GitHub Actions
### Automatic staging deploy
- Any push to `main` runs a `plan` then `apply` to **staging**.

### Manual deploy (staging or production)
Run workflow: `terraform-deploy`
- Choose `environment`: `staging` or `production`
- Choose `mode`: `plan` or `apply`

Notes:
- Production runs should be protected by GitHub Environment approvals.

## 5) Destroy using GitHub Actions
Run workflow: `terraform-destroy`
- Choose `environment`
- Enter `confirm=DESTROY`

## 6) Local deploy (optional)
If you want to run locally instead of CI:

```powershell
# Example: staging
$env:TF_VAR_environment = "staging"
$env:TF_VAR_location = "westeurope"
$env:TF_VAR_sql_admin_password = "<set-a-strong-password>"

terraform init `
  -backend-config="resource_group_name=<TFSTATE_RESOURCE_GROUP>" `
  -backend-config="storage_account_name=<TFSTATE_STORAGE_ACCOUNT>" `
  -backend-config="container_name=<TFSTATE_CONTAINER>" `
  -backend-config="key=ecomm.staging.tfstate"

terraform validate
terraform plan -out tfplan
terraform apply -auto-approve tfplan
```

## Outputs
After apply, Terraform outputs include:
- Frontend URL
- API URL
- SQL server FQDN and database name

## Troubleshooting
- If Key Vault references don’t resolve in App Service:
  - Confirm the Web App’s managed identity has `Key Vault Secrets User` on the vault
  - Confirm Key Vault networking allows access
- If blob access fails:
  - Confirm API identity has `Storage Blob Data Contributor` on the storage account
  - Confirm your app uses Managed Identity (no connection string keys)
- If Terraform apply fails on role assignments:
  - Ensure your OIDC principal has permissions to create role assignments

## Next steps (recommended hardening)
- Private networking (VNet integration + private endpoints for SQL/Storage/Key Vault)
- WAF (Front Door / App Gateway) if you want an internet-facing security layer
- Monitoring (Application Insights + Log Analytics)
- Replace SQL admin auth with Entra ID / managed identity auth for the API
