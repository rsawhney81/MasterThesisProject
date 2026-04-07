variable "app_name" {
  description = "Application name used for naming."
  type        = string
  default     = "ecomm"
}

variable "environment" {
  description = "Deployment environment. Must be 'staging' or 'production'."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be one of: staging, production."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "region_short" {
  description = "Short region code used for naming."
  type        = string
  default     = "weu"
}

variable "owner_email" {
  description = "Owner email for tagging (non-secret)."
  type        = string
  default     = "owner@company.com"
}

variable "sql_admin_login" {
  description = "SQL administrator login name."
  type        = string
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "SQL administrator password (stored in Key Vault)."
  type        = string
  sensitive   = true
}
