# Deployment Plan — Node.js E-commerce (Staging + Production)

Status: Workflow Complete (Stages 1–4 approved)

## 1) Summary
Deploy a Node.js e-commerce application with:
- Frontend on Azure App Service (Web App)
- REST API backend on Azure App Service (Web App)
- Azure SQL Database for product + order data
- Azure Blob Storage for product images
- Azure Key Vault for secrets

Environments:
- `staging` in West Europe
- `production` in West Europe

## Stage Log
- Stage 1 (Architecture): input received (Node.js e-commerce; Web App frontend + REST API; Azure SQL; Blob; Key Vault; staging+production in West Europe; ~500 concurrent users; security important). Output: `docs/ecomm-azure-architecture.puml` + `docs/ecomm-azure-architecture.png`. Approval: Approved.
- Stage 2 (Terraform IaC): output produced: `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`. Approval: Approved.
- Stage 3 (CI/CD): output produced: `.github/workflows/deploy.yml`, `.github/workflows/destroy.yml`. Approval: Approved.
- Stage 4 (README): output produced: `README.md`. Approval: Approved.

## 2) Workspace Reality Check
- This workspace currently contains only `.github/` and no Node.js application code was detected (no `package.json`, no JS/TS sources).
- The plan below assumes we will either:
  1) add your existing code into a standard layout (`src/frontend`, `src/api`), or
  2) scaffold minimal placeholder apps only to validate the Azure infrastructure.

## 3) Architecture (Target)
Per-environment isolated resources (recommended):
- Resource Group: one per environment
- App Service Plan (Linux)
- Web App: `frontend` (serves SPA/SSR/static)
- Web App: `api` (Node.js REST)
- Azure SQL Server + Database
- Storage Account + Blob container (e.g., `product-images`)
- Key Vault (secrets + references)

### Identity & Secrets
- Enable System-Assigned Managed Identity on both Web Apps.
- Key Vault:
  - Store secrets needed by the application (e.g., SQL password if using SQL auth).
  - Use App Service Key Vault references (`@Microsoft.KeyVault(...)`) for app settings.
- Prefer *no* shared keys for Storage:
  - Use Managed Identity + RBAC (`Storage Blob Data Contributor`) for the API to read/write blobs.

> Note: Using Microsoft Entra ID auth to Azure SQL (Managed Identity) is possible and can eliminate SQL passwords entirely, but it requires app-level driver configuration and database AAD admin setup. This plan defaults to SQL auth + Key Vault secret for fastest path, and can be upgraded to AAD/MI after first deployment.

## 4) Sizing Assumptions (500 concurrent peak)
- Production:
  - App Service Plan: Premium v3 (Linux) to support scaling and sustained load.
  - Initial instance count: 2
  - Autoscale: target 2–4 instances (rules based on CPU/requests) — exact rules can be tuned after baseline testing.
- Staging:
  - Smaller plan (Basic/Standard) with 1 instance is typically sufficient.

## 5) Deployment Approach (Recipe)
- Use Terraform as IaC (per `.github/agents/InfraAgentDevOpsAI.agent.md`).
- Multi-environment:
  - `staging` in West Europe
  - `production` in West Europe

Outputs to generate after approval:
- Terraform IaC: `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`
- Minimal app config wiring (App Settings, Key Vault references, Managed Identity role assignments)

## 6) Naming & Tags (Proposed)
- Prefix: `ecomm` (adjustable)
- Region: `westeurope`
- Example names (actual names may vary due to global uniqueness constraints):
  - Resource group: `rg-ecomm-weu-staging`, `rg-ecomm-weu-production`
  - Key Vault: `kv-ecomm-weu-staging`, `kv-ecomm-weu-production`
  - Web apps: `app-ecomm-frontend-staging`, `app-ecomm-api-staging` (and `-production`)
  - Storage: `stecommweu<env><unique>`
  - SQL server: `sqlecommweu<env><unique>`

## 7) Security Baseline
- HTTPS only on Web Apps
- TLS minimum 1.2
- Key Vault purge protection enabled (do not disable)
- RBAC least privilege for managed identities:
  - Key Vault: `Key Vault Secrets User` (read secrets)
  - Storage: `Storage Blob Data Contributor` (API identity)
- Do not commit secrets to git; secrets entered into Key Vault at provision time or via `azd env set`.

## 7b) AZD + Bicep Rule Compliance (Implemented)
- User-Assigned Managed Identity exists: `Microsoft.ManagedIdentity/userAssignedIdentities` is created and attached to both Web Apps.
- Resource group has tag `azd-env-name = environmentName`: resource group is created at subscription scope with only this tag.
- Parameters: `environmentName=${AZURE_ENV_NAME}`, `location=${AZURE_LOCATION}`, `resourceGroupName=rg-${AZURE_ENV_NAME}` are in `infra/main.parameters.json`.
- `azd-service-name` tags: applied only to App Service Web Apps and match `azure.yaml` service names (`api`, `frontend`).
- Required output: `RESOURCE_GROUP_ID` is exported from `infra/main.bicep`.
- Expected files: `infra/main.bicep` and `infra/main.parameters.json` exist.
- Resource token format: `uniqueString(subscription().id, location, environmentName)` used (subscription scope).
- Naming pattern: resources use `az{<=3charPrefix}{token}` with truncation for services with stricter naming limits.
- App Service site extension: `Microsoft.Web/sites/siteextensions` created for both Web Apps.
- Storage hardening: `allowSharedKeyAccess=false` (disable local auth) and blob public access disabled.

## 8) Open Questions (Answering these makes generation precise)
1) Do you want me to scaffold minimal placeholder Node apps (frontend + API) to validate infra, or will you bring your real app code into this workspace?
2) Any preference for Node version (e.g., 20 LTS) and frontend framework (Next.js vs React static build)?
3) Should SQL be provisioned with SQL authentication (password in Key Vault) for first deployment, or do you want the more secure Entra ID / Managed Identity approach from day one?

## 9) Execution Steps (Terraform Workflow)
Stage 1 — Architecture
1) Architecture diagram (PlantUML): `docs/ecomm-azure-architecture.puml`
2) Approval gate: user must approve architecture before Terraform generation.

Stage 2 — Terraform IaC
3) Generate Terraform: `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`
4) Approval gate: user must approve Terraform before CI/CD workflow generation.

Stage 3 — CI/CD
5) Generate GitHub Actions workflows under `.github/workflows/`

Stage 4 — Deployment Documentation
6) Generate `README.md` runbook
