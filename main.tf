locals {
  name_prefix = "${var.app_name}-${var.environment}-${var.region_short}"

  tags = {
    environment = var.environment
    owner       = var.owner_email
    app         = var.app_name
  }

  app_service_sku = var.environment == "production" ? "P1v3" : "S1"
  sql_sku_name    = var.environment == "production" ? "S2" : "S0"
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name_prefix}"
  location = var.location

  tags = merge(local.tags, {
    # Parity with multi-env tooling: convenient env tag.
    "azd-env-name" = var.environment
  })
}

resource "azurerm_key_vault" "kv" {
  name                = substr(replace("kv-${local.name_prefix}-${random_string.suffix.result}", "-", ""), 0, 24)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Security requirements
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  enable_rbac_authorization  = true

  tags = local.tags
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_storage_account" "images" {
  name                     = substr(lower(replace("st${local.name_prefix}${random_string.suffix.result}", "-", "")), 0, 24)
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false

  # Disable local auth (shared key) per security requirements.
  shared_access_key_enabled = false

  tags = local.tags
}

resource "azurerm_storage_container" "product_images" {
  name                  = "product-images"
  storage_account_name  = azurerm_storage_account.images.name
  container_access_type = "private"
}

resource "azurerm_service_plan" "asp" {
  name                = "asp-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  os_type      = "Linux"
  sku_name     = local.app_service_sku
  worker_count = var.environment == "production" ? 2 : 1

  tags = local.tags
}

resource "azurerm_linux_web_app" "api" {
  name                = "api-${local.name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.asp.id

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    minimum_tls_version = "1.2"

    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "AZURE_ENV_NAME"                 = var.environment

    "SQL_SERVER"   = azurerm_mssql_server.sql.fully_qualified_domain_name
    "SQL_DATABASE" = azurerm_mssql_database.db.name
    "SQL_USER"     = var.sql_admin_login

    # Key Vault reference; secret is stored in Key Vault.
    # Note: the secret value is still present in Terraform state. Protect state access accordingly.
    "SQL_PASSWORD" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.sql_admin_password.versionless_id})"

    "STORAGE_ACCOUNT_NAME" = azurerm_storage_account.images.name
    "BLOB_CONTAINER"       = azurerm_storage_container.product_images.name
    "KEY_VAULT_NAME"       = azurerm_key_vault.kv.name
  }

  tags = local.tags
}

resource "azurerm_linux_web_app" "frontend" {
  name                = "web-${local.name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.asp.id

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    minimum_tls_version = "1.2"

    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "AZURE_ENV_NAME"                 = var.environment
    "API_BASE_URL"                   = "https://${azurerm_linux_web_app.api.default_hostname}"
  }

  tags = local.tags
}

resource "azurerm_mssql_server" "sql" {
  name                         = "sql-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"

  public_network_access_enabled = true

  tags = local.tags
}

resource "azurerm_mssql_database" "db" {
  name      = "db-${local.name_prefix}"
  server_id = azurerm_mssql_server.sql.id

  sku_name = local.sql_sku_name

  tags = local.tags
}

# Simplest baseline: allow Azure services (including App Service) to access SQL.
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# RBAC: allow API identity to read secrets.
resource "azurerm_role_assignment" "api_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.api.identity[0].principal_id
}

# RBAC: allow frontend identity to read secrets if needed in the future.
resource "azurerm_role_assignment" "frontend_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.frontend.identity[0].principal_id
}

# RBAC: allow API identity to access blob data plane.
resource "azurerm_role_assignment" "api_storage_blob_contributor" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_web_app.api.identity[0].principal_id
}
