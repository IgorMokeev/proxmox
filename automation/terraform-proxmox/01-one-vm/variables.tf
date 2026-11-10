# =====================================================================
# variables.tf — ПЕРЕМЕННЫЕ СЦЕНАРИЯ 1 (одна ВМ из шаблона)
# ---------------------------------------------------------------------
# Переменная — это «настройка» с именем. Значение по умолчанию (default)
# записано здесь, но свои значения удобнее вписывать в файл
# terraform.tfvars (его вы создаёте копированием terraform.tfvars.example).
# Всё, что в terraform.tfvars, перекрывает default отсюда.
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
  sensitive   = true # Terraform не будет показывать значение в выводе
  description = "API-токен: user@realm!имя=секрет. Секрет нигде не храните в открытом виде, лучше через TF_VAR_pm_api_token (см. README)."
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
# Шаблон и новая ВМ
# ---------------------------------------------------------------------

variable "template_id" {
  type        = number
  default     = 11243 # ubuntu24cloud-tmpl из ваших скриптов
  description = "ID шаблона, из которого делаем ВМ. Ubuntu 11243, Debian 10133, CentOS 180103 (если не меняли в скриптах)."

  validation {
    condition     = var.template_id >= 100
    error_message = "ID шаблона должен быть числом >= 100."
  }
}

variable "vm_id" {
  type        = number
  default     = 5001
  description = "ID НОВОЙ ВМ. Должен быть свободен в Proxmox."
}

variable "vm_name" {
  type        = string
  default     = "test-vm-01"
  description = "Имя новой ВМ (латиница, цифры, дефис)."
}

# ---------------------------------------------------------------------
# Железо новой ВМ
# ---------------------------------------------------------------------

variable "cores" {
  type        = number
  default     = 2
  description = "Количество ядер CPU."
}

variable "memory_mb" {
  type        = number
  default     = 4096
  description = "Оперативная память, МБ."
}

variable "cpu_type" {
  type        = string
  default     = "x86-64-v2-AES"
  description = "Тип CPU. Для Ubuntu/Debian: x86-64-v2-AES. Для CentOS 10 ОБЯЗАТЕЛЬНО x86-64-v3 (иначе не загрузится)."
}

variable "bios" {
  type        = string
  default     = "ovmf"
  description = "BIOS должен совпадать с шаблоном. Ваши скрипты Ubuntu/Debian/CentOS используют ovmf (UEFI)."
}

# ---------------------------------------------------------------------
# Сеть
# ---------------------------------------------------------------------

variable "vm_ip" {
  type        = string
  default     = "10.1.1.80/24"
  description = "Статический IP ВМ с маской. Свободный пул: 10.1.1.80 - 10.1.1.108."
}

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
  description = "Сетевой мост Proxmox (как в шаблоне)."
}
