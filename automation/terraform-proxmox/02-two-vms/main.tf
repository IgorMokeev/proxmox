# =====================================================================
# main.tf — СЦЕНАРИЙ 2: НЕСКОЛЬКО ВМ ИЗ РАЗНЫХ ШАБЛОНОВ
# ---------------------------------------------------------------------
# `for_each` создаёт по одному ресурсу на каждую запись переменной `vms`.
# Меняете список в terraform.tfvars — меняется число ВМ. Код трогать не надо.
# ВМ только СОЗДАЮТСЯ, но НЕ запускаются: запускайте вручную.
# =====================================================================

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = var.pm_node
  vm_id     = each.value.vm_id
  tags      = ["terraform"]

  # --- НЕ запускать ВМ после создания ---------------------------------
  started = false
  on_boot = false

  # --- Параметры, повторяющие шаблон ----------------------------------
  bios          = var.bios
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  cpu {
    cores = each.value.cores
    type  = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory_mb
  }

  agent {
    enabled = true
  }

  vga {
    type = "serial0"
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
    vm_id   = each.value.template_id
    full    = true
    retries = 3
  }

  # --- Cloud-Init: статический IP -------------------------------------
  # Пользователь (la), пароль и SSH-ключ остаются из шаблона.
  initialization {
    datastore_id = "local-lvm"
    interface    = "scsi1"

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }
  }
}
