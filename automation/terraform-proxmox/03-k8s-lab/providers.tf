# =====================================================================
# providers.tf — ПОДКЛЮЧЕНИЕ К PROXMOX
# ---------------------------------------------------------------------
# Здесь Terraform узнаёт, какой провайдер (плагин) использовать и как
# подключаться к серверу Proxmox. Обычно этот файл менять НЕ нужно:
# все значения берутся из переменных (см. variables.tf / terraform.tfvars).
# =====================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.119.0" # версия закреплена, чтобы всё работало одинаково
    }
  }
}

provider "proxmox" {
  endpoint  = var.pm_endpoint
  api_token = var.pm_api_token
  insecure  = var.pm_insecure # true = не проверять самоподписанный сертификат
}
