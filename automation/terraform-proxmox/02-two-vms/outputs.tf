# =====================================================================
# outputs.tf — ЧТО ПОКАЗАТЬ ПОСЛЕ `terraform apply`
# =====================================================================

output "vms" {
  description = "Созданные ВМ: имя => ID и IP"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => { vm_id = vm.vm_id, ip = var.vms[name].ip }
  }
}

output "next_step" {
  description = "Что делать дальше"
  value       = "ВМ созданы, но НЕ запущены. Запуск вручную: qm start <vm_id> или кнопка Start в веб-интерфейсе. Вход: ssh la@<IP>"
}
