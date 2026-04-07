output "resource_group_name" {
  description = "Resource group name for this environment."
  value       = azurerm_resource_group.rg.name
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.kv.name
}

output "storage_account_name" {
  description = "Storage account for product images."
  value       = azurerm_storage_account.images.name
}

output "images_container_name" {
  description = "Blob container for product images."
  value       = azurerm_storage_container.product_images.name
}

output "api_url" {
  description = "API base URL."
  value       = "https://${azurerm_linux_web_app.api.default_hostname}"
}

output "frontend_url" {
  description = "Frontend base URL."
  value       = "https://${azurerm_linux_web_app.frontend.default_hostname}"
}

output "sql_server_fqdn" {
  description = "SQL Server FQDN."
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "SQL database name."
  value       = azurerm_mssql_database.db.name
}
