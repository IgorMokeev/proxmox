# =====================================================================
# variables.tf — ПЕРЕМЕННЫЕ СЦЕНАРИЯ 2 (несколько ВМ из разных шаблонов)
# ---------------------------------------------------------------------
# Главная переменная — `vms`: список машин. У каждой своя строка со своим
# шаблоном, ID, IP. Хотите 3 машины — добавьте ещё одну строку в
# terraform.tfvars. Свои значения вписывайте в terraform.tfvars.
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
# Сеть (общая для всех ВМ)
# ---------------------------------------------------------------------

variable "gateway" {
  type        = string
  default     = "10.1.1.1"
  description = "Шлюз (роутер)."
}

variable "dns_servers" {
  type        = list(string)
  default     = ["10.1.1.1"]
  description = "DNS-серверы."
}

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Сетевой мост Proxmox (как в шаблонах)."
}

variable "bios" {
  type        = string
  default     = "ovmf"
  description = "BIOS должен совпадать с шаблонами. Скрипты Ubuntu/Debian/CentOS используют ovmf (UEFI)."
}

# ---------------------------------------------------------------------
# Список ВМ
# ---------------------------------------------------------------------
# Ключ (слева) — имя ВМ. Поля:
#   template_id — ID шаблона (обязательно)
#   vm_id       — ID новой ВМ, должен быть свободен (обязательно)
#   ip          — статический IP с маской, из пула 10.1.1.80-108 (обязательно)
#   cores / memory_mb / cpu_type — необязательные, есть значения по умолчанию
# Для CentOS 10 обязательно cpu_type = "x86-64-v3".

variable "vms" {
  type = map(object({
    template_id = number
    vm_id       = number
    ip          = string
    cores       = optional(number, 2)
    memory_mb   = optional(number, 4096)
    cpu_type    = optional(string, "x86-64-v2-AES")
  }))

  default = {
    "ubuntu-vm-01" = {
      template_id = 11243 # Ubuntu 24.04
      vm_id       = 5101
      ip          = "10.1.1.81/24"
    }
    "debian-vm-01" = {
      template_id = 10133 # Debian 13
      vm_id       = 5102
      ip          = "10.1.1.82/24"
    }
  }

  description = "Список создаваемых ВМ (см. пояснение выше)."
}
