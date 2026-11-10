# =====================================================================
# main.tf — СЦЕНАРИЙ 3: БАЗОВЫЙ СТЕНД KUBERNETES
# ---------------------------------------------------------------------
# Создаются 3 ВМ: k8s-master, k8s-worker1, k8s-worker2 (НЕ запускаются).
# При ПЕРВОМ запуске каждой ВМ cloud-init (файл k8s-vendor.yaml) сам
# установит containerd, kubeadm, kubelet, kubectl. Сам кластер
# (kubeadm init / join) вы создаёте вручную — это и есть учёба.
# =====================================================================

locals {
  nodes = {
    "k8s-master" = {
      vm_id  = var.first_vm_id
      ip     = var.master_ip
      cores  = var.master_cores
      memory = var.master_memory_mb
    }
    "k8s-worker1" = {
      vm_id  = var.first_vm_id + 1
      ip     = var.worker1_ip
      cores  = var.worker_cores
      memory = var.worker_memory_mb
    }
    "k8s-worker2" = {
      vm_id  = var.first_vm_id + 2
      ip     = var.worker2_ip
      cores  = var.worker_cores
      memory = var.worker_memory_mb
    }
  }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  name      = each.key
  node_name = var.pm_node
  vm_id     = each.value.vm_id
  tags      = ["terraform", "k8s"]

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
    type  = var.cpu_type
  }

  memory {
    dedicated = each.value.memory
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
    vm_id   = var.template_id
    full    = true
    retries = 3
  }

  # --- Cloud-Init -----------------------------------------------------
  initialization {
    datastore_id = "local-lvm"
    interface    = "scsi1"

    # Наш файл подготовки к Kubernetes. Он ЗАМЕНЯЕТ snippet шаблона
    # (часовой пояс и qemu-guest-agent в нём уже есть).
    # Пользователь (la), пароль и SSH-ключ остаются из шаблона.
    vendor_data_file_id = var.k8s_snippet

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
