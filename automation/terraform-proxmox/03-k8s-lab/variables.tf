# =====================================================================
# variables.tf — ПЕРЕМЕННЫЕ СЦЕНАРИЯ 3 (стенд Kubernetes)
# ---------------------------------------------------------------------
# Стенд: 1 control-plane (master) + 2 worker, все из ОДНОГО шаблона.
# ВАЖНО: шаблон должен быть на базе Debian/Ubuntu (используется apt).
# CentOS (dnf) для этого сценария НЕ подходит.
# Свои значения вписывайте в terraform.tfvars.
# =====================================================================

# ---------------------------------------------------------------------
# Подключение к Proxmox
# ---------------------------------------------------------------------

variable "pm_endpoint" {
  type        = string
  default     = "https://10.1.1.20:8006/"
  description = "Адрес API Proxmox (с https:// и портом 8006)."
}

variable "pm_api_token" {
  type        = string
  sensitive   = true
  description = "API-токен: user@realm!имя=секрет. Лучше передавать через TF_VAR_pm_api_token (см. README)."
}

variable "pm_insecure" {
  type        = bool
  default     = true
  description = "true = не проверять сертификат (у Proxmox он по умолчанию самоподписанный)."
}

variable "pm_node" {
  type        = string
  default     = "archimedes"
  description = "Имя узла Proxmox (как в левом дереве веб-интерфейса)."
}

# ---------------------------------------------------------------------
# Шаблон
# ---------------------------------------------------------------------

variable "template_id" {
  type        = number
  default     = 11243 # Ubuntu 24.04
  description = "ID шаблона Debian/Ubuntu для всех узлов. Ubuntu 11243, Debian 10133."

  validation {
    condition     = var.template_id >= 100
    error_message = "ID шаблона должен быть числом >= 100."
  }
}

variable "cpu_type" {
  type        = string
  default     = "x86-64-v2-AES"
  description = "Тип CPU (для Ubuntu/Debian: x86-64-v2-AES)."
}

variable "bios" {
  type        = string
  default     = "ovmf"
  description = "BIOS должен совпадать с шаблоном (ваши скрипты: ovmf)."
}

# ---------------------------------------------------------------------
# Узлы кластера
# ---------------------------------------------------------------------

variable "first_vm_id" {
  type        = number
  default     = 5201
  description = "ID master-узла; worker'ы получат следующие два ID (5202, 5203). Все три должны быть свободны."
}

variable "master_ip" {
  type        = string
  default     = "10.1.1.90/24"
  description = "IP master-узла с маской (пул 10.1.1.80-108)."
}

variable "worker1_ip" {
  type        = string
  default     = "10.1.1.91/24"
  description = "IP первого worker с маской."
}

variable "worker2_ip" {
  type        = string
  default     = "10.1.1.92/24"
  description = "IP второго worker с маской."
}

variable "master_cores" {
  type    = number
  default = 2 # kubeadm требует минимум 2 CPU на master
}

variable "master_memory_mb" {
  type    = number
  default = 4096
}

variable "worker_cores" {
  type    = number
  default = 2
}

variable "worker_memory_mb" {
  type    = number
  default = 3072
}

# ---------------------------------------------------------------------
# Сеть
# ---------------------------------------------------------------------

variable "gateway" {
  type        = string
  default     = "10.1.1.1"
  description = "Шлюз (роутер)."
}

variable "dns_servers" {
  type        = list(string)
  default     = ["10.1.1.1"]
  description = "DNS-серверы (нужны, чтобы скачать пакеты Kubernetes)."
}

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Сетевой мост Proxmox (как в шаблоне)."
}

# ---------------------------------------------------------------------
# Cloud-init файл подготовки узлов
# ---------------------------------------------------------------------

variable "k8s_snippet" {
  type        = string
  default     = "local:snippets/k8s-vendor.yaml"
  description = "Файл k8s-vendor.yaml (лежит рядом), который ВЫ ВРУЧНУЮ копируете на Proxmox в /var/lib/vz/snippets/ (шаг 1 в README)."
}
