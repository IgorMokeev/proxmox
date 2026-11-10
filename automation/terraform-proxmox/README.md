
Terraform + Proxmox: шпаргалка
На основании созданных proxmox cloud init шаблонов, автоматизируем создание стендов виртуальных машин

Пример установки Terraform на сервер debian13
скачиваем https://developer.hashicorp.com/terraform/install Binary download AMD64 terraform_1.17.1_linux_amd64.zip
mkdir terraform-proxmox
mv terraform_1.17.1_linux_amd64.zip terraform-proxmox/
sudo apt update && sudo apt install -y curl unzip
unzip terraform_1.17.1_linux_amd64.zip
sudo chown root:root terraform
sudo mv terraform /usr/local/bin/
или sudo install -m 0755 terraform /usr/local/bin/terraform
Проверка:
command -v terraform
terraform version

Создаем Terraform зеркало на Yandex
nano ~/.terraformrc

provider_installation {
  network_mirror {
    url = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}

Выбираем Terraform провайдер для proxmox (он будет по умолчанию в конфигурациях)
выбираем provider https://registry.terraform.io/
в поиске пишем proxmox
Я использовал bgp - больше загрузок в неделю (более популярный и чаще обновляемые версии)
почитать его описание - https://registry.terraform.io/providers/bpg/proxmox/latest



Пример (для понимания) на которые настроены конфиги: Proxmox `https://10.1.1.20:8006`, узел `archimedes`,
сеть `10.1.1.0/24`, шлюз и DNS `10.1.1.1`, провайдер `bpg/proxmox 0.119.0`.

## Что внутри

```
proxmox-lab/
├── README.md                  <- этот файл
├── .gitignore
├── 01-one-vm/                 Сценарий 1: ОДНА ВМ из шаблона (ID шаблона — переменная)
├── 02-two-vms/                Сценарий 2: НЕСКОЛЬКО ВМ из разных шаблонов (по умолчанию 2)
└── 03-k8s-lab/                Сценарий 3: стенд Kubernetes (master + 2 worker)
    └── k8s-vendor.yaml        cloud-init файл, копируется на Proxmox вручную
```

В каждой папке одинаковый набор файлов:

| Файл | Зачем |
|---|---|
| `providers.tf` | Подключение к Proxmox. Обычно не меняется |
| `variables.tf` | Список всех настроек с описаниями и значениями по умолчанию |
| `main.tf` | Сами ВМ (то, что создаётся) |
| `outputs.tf` | Что напечатать после создания (имена, IP) |
| `terraform.tfvars.example` | Образец ВАШИХ значений. Копируется в `terraform.tfvars` |

**Каждая папка — независимый проект.** Команды `terraform ...` всегда выполняются внутри нужной папки.
Сценарии можно держать одновременно: у них разные ID ВМ и разные IP.

## Что создаётся по умолчанию

| Сценарий | ВМ | ID | IP |
|---|---|---|---|
| 1 | `test-vm-01` (Ubuntu 11243) | 5001 | 10.1.1.80 |
| 2 | `ubuntu-vm-01` (11243), `debian-vm-01` (10133) | 5101, 5102 | 10.1.1.81, 10.1.1.82 |
| 3 | `k8s-master`, `k8s-worker1`, `k8s-worker2` (11243) | 5201–5203 | 10.1.1.90, .91, .92 |

Все ВМ создаются **остановленными**. Запускайте сами: кнопка Start в веб-интерфейсе или `qm start <ID>` на Proxmox.

---

## Шаг 0. Один раз: создать API-токен для Terraform

На сервере Proxmox (домашняя лаборатория для изучения) консоль или SSH под root:

```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve tf --privsep 0
```

Последняя команда покажет `value` — это секрет токена, он виден **один раз**. Полный токен выглядит так:

```
terraform@pve!tf=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Если пользователь `terraform@pve` уже есть, пропустите первую команду. Роль `Administrator` взята ради простоты лаборатории.

## Шаг 1. Настроить сценарий

```bash
cd proxmox-lab/01-one-vm            # или 02-two-vms, или 03-k8s-lab
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars               # впишите токен, при желании свои ID/IP
```

Токен можно не писать в файл, а передать через переменную окружения (безопаснее):

```bash
export TF_VAR_pm_api_token='terraform@pve!tf=СЕКРЕТ'
```

(тогда строку `pm_api_token` из `terraform.tfvars` уберите).

## Шаг 2. Четыре команды Terraform

```bash
terraform init       # один раз на папку: скачивает провайдер
terraform plan       # ПОКАЗЫВАЕТ, что будет сделано, ничего не меняя
terraform apply      # создаёт (спросит подтверждение: введите yes)
terraform destroy    # удаляет всё, что создал этот проект (шаблоны не трогает)
```

Привычка №1: всегда читайте вывод `plan`. Ожидаемо: сценарий 1 — `1 to add`, сценарий 2 — `2 to add`, сценарий 3 — `3 to add`.

---

## Сценарий 1 — одна ВМ

Что менять в `terraform.tfvars`: `template_id` (ID шаблона), `vm_id`, `vm_name`, `vm_ip`.
Для шаблона CentOS 10 (180103) обязательно `cpu_type = "x86-64-v3"`.

## Сценарий 2 — несколько ВМ из разных шаблонов

Переменная `vms` — это список. Одна запись — одна ВМ:

```hcl
vms = {
  "ubuntu-vm-01" = { template_id = 11243, vm_id = 5101, ip = "10.1.1.81/24" }
  ...
}
```

Хотите три машины — добавьте ещё блок (образец с CentOS закомментирован в `terraform.tfvars.example`).
Код `main.tf` трогать не нужно.

## Сценарий 3 — стенд Kubernetes

Работает только с шаблоном на **Debian/Ubuntu** (используется `apt`). CentOS не подойдёт.

**3.1. Положить cloud-init файл на Proxmox (один раз, ДО `terraform apply`):**

```bash
cd proxmox-lab/03-k8s-lab
scp k8s-vendor.yaml root@10.1.1.20:/var/lib/vz/snippets/
```

(Эта папка уже есть, раз ваши скрипты шаблонов пишут snippets на хранилище `local`.)

**3.2. Создать ВМ:**

```bash
cp terraform.tfvars.example terraform.tfvars   # впишите токен
terraform init
terraform plan
terraform apply
```

**3.3. Запустить три ВМ вручную** и подождать 3–7 минут: cloud-init скачивает и ставит Kubernetes. На каждом узле проверьте:

```bash
ssh la@10.1.1.90
cloud-init status --wait        # дождаться "status: done"
ls /var/lib/k8s-node-ready      # файл должен быть
kubeadm version
```

Если что-то не так: `sudo tail -n 100 /var/log/cloud-init-output.log`.

**3.4. Создать кластер вручную.** На **master** (10.1.1.90):

```bash
sudo kubeadm init --apiserver-advertise-address=10.1.1.90 --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
sudo kubeadm token create --print-join-command
```

Скопируйте напечатанную команду `kubeadm join ...` и выполните её с `sudo` на **каждом worker** (10.1.1.91 и 10.1.1.92).

Проверка на master:

```bash
kubectl get nodes        # через 1-2 минуты все 3 узла Ready
kubectl create deployment nginx --image=nginx --replicas=2
kubectl get pods -o wide
```

Версия Kubernetes задаётся в `k8s-vendor.yaml` (две строки `v1.36`).
Пересоздать стенд: `terraform destroy`, затем `terraform apply`.

---

## Проверка после первого `apply`

Эти конфиги я написал по документации провайдера, на вашем Proxmox они не запускались. Поэтому после создания:

1. `terraform plan` ещё раз: должно быть `No changes`. Если Terraform хочет «исправить» только что созданные ВМ, не применяйте, а покажите вывод.
2. На Proxmox: `qm config <ID новой ВМ>` и сравните с `qm config <ID шаблона>`: `bios`, `machine`, `cpu`, `scsi0`, `scsi1` (cloudinit), `efidisk0`, `ciuser`, `sshkeys` должны совпадать с шаблоном, отличаться должны имя, ядра/память и `ipconfig0`.
3. После первого запуска ВМ проверьте вход `ssh la@<IP>`.

## Частые проблемы

| Симптом | Что делать |
|---|---|
| `401` / `permission denied` | Проверьте токен целиком (`user@realm!имя=секрет`) и что он создан с `--privsep 0` |
| `x509: certificate ...` | В `terraform.tfvars` укажите `pm_insecure = true` (по умолчанию уже так) |
| `VM ... already exists` | Выбранный `vm_id` занят. Поменяйте на свободный |
| `can't lock file ... timeout` при клонировании | Несколько клонов одного шаблона мешают друг другу: `terraform apply -parallelism=1` |
| Сценарий 3: `snippets ... does not exist` | Не выполнен шаг 3.1 (scp) |
| ВМ с CentOS 10 не загружается | В сценариях 1/2 для неё нужен `cpu_type = "x86-64-v3"` |
| Сценарий 3: нет интернета на узле | Проверьте `gateway` и `dns_servers`; cloud-init качает пакеты из интернета |
| Не входит по SSH | Используйте ключ, публичная часть которого лежит в `/root/configs/authorized_keys` на Proxmox: `ssh -i ~/.ssh/id_ed25519 la@IP` |

## Полезно знать

- Файл `terraform.tfstate` в папке сценария — «память» Terraform о созданном. Не удаляйте его и не публикуйте. `terraform.tfvars` тоже не публикуйте (в `.gitignore` уже добавлены).
- Если ВМ из Terraform удалить вручную в Proxmox, `terraform apply` создаст её заново.
- Изменили `main.tf`/переменные и хотите применить: `terraform plan`, затем `terraform apply`. Для смены CPU/RAM у запущенной ВМ потребуется перезапуск.
- Hash пароля и SSH-ключ пользователя `la` берутся из шаблона (см. ваши скрипты шаблонов), Terraform их не меняет.
