# =====================================================================
# outputs.tf — ЧТО ПОКАЗАТЬ ПОСЛЕ `terraform apply`
# =====================================================================

output "vm" {
  description = "Созданная ВМ"
  value = {
    name  = proxmox_virtual_environment_vm.vm.name
    vm_id = proxmox_virtual_environment_vm.vm.vm_id
    ip    = var.vm_ip
  }
}

output "next_step" {
  description = "Что делать дальше"
  value       = "ВМ создана, но НЕ запущена. Запуск: qm start ${var.vm_id} (на Proxmox) или кнопка Start в веб-интерфейсе. Вход: ssh la@${split("/", var.vm_ip)[0]}"
}
