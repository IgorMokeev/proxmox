# =====================================================================
# main.tf — СЦЕНАРИЙ 1: ОДНА ВМ ИЗ ШАБЛОНА
# ---------------------------------------------------------------------
# Ресурс (resource) — это то, что Terraform создаёт. Здесь — одна ВМ,
# клонированная из шаблона. ВМ только СОЗДАЁТСЯ, но НЕ запускается:
# запускайте вручную (веб-интерфейс или `qm start <vm_id>`).
# =====================================================================

resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = var.pm_node
  vm_id     = var.vm_id
  tags      = ["terraform"]

  # --- НЕ запускать ВМ после создания ---------------------------------
  started = false
  on_boot = false

  # --- Параметры, повторяющие шаблон ----------------------------------
  # Они совпадают с вашими скриптами шаблонов. Указаны явно, чтобы
  # провайдер не подставил свои значения по умолчанию вместо шаблонных.
  bios          = var.bios
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26" # Linux
  }

  cpu {
    cores = var.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
  }

  agent {
    enabled = true # qemu-guest-agent (ставится cloud-init из шаблона)
  }

  vga {
    type = "serial0" # как в шаблоне: консоль через serial
  }

  serial_device {
    device = "socket"
  }

  network_device {
    bridge   = var.bridge
    model    = "virtio"
    firewall = true
  }

  # --- Клонирование из шаблона ----------------------------------------
  clone {
    vm_id   = var.template_id
    full    = true # полная независимая копия диска
    retries = 3
  }

  # --- Cloud-Init: статический IP -------------------------------------
  # Пользователь (la), пароль и SSH-ключ остаются из шаблона.
  initialization {
    datastore_id = "local-lvm"
    interface    = "scsi1" # так диск cloud-init подключён в ваших шаблонах

    ip_config {
      ipv4 {
        address = var.vm_ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }
  }
}
