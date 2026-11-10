# =====================================================================
# outputs.tf — ЧТО ПОКАЗАТЬ ПОСЛЕ `terraform apply`
# =====================================================================

output "nodes" {
  description = "Узлы кластера: имя => ID и IP"
  value = {
    for name, n in local.nodes :
    name => { vm_id = n.vm_id, ip = n.ip }
  }
}

output "ssh_commands" {
  description = "Команды входа (после ручного запуска ВМ)"
  value       = [for name, n in local.nodes : "ssh la@${split("/", n.ip)[0]}   # ${name}"]
}

output "next_step" {
  description = "Что делать дальше"
  value       = "ВМ созданы, но НЕ запущены. Запустите все три вручную, подождите 3-7 минут (cloud-init ставит Kubernetes), дальше см. README, раздел про сценарий 3."
}
