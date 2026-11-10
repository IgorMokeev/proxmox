# Terraform + Proxmox: шпаргалка

Автоматизация создания стендов виртуальных машин в Proxmox VE из готовых Cloud-Init шаблонов с помощью Terraform.

Три готовых сценария, от одной ВМ до кластера Kubernetes. Каждый сценарий — независимый Terraform-проект.

> **Важно.** Конфиги написаны по документации провайдера и могут отличаться в поведении на разных установках Proxmox. После первого `apply` пройдите [чек-лист проверки](#проверка-после-первого-apply).

## Содержание

- [Что нужно](#что-нужно)
- [Установка Terraform](#установка-terraform)
- [Зеркало и провайдер](#зеркало-и-провайдер)
- [Структура репозитория](#структура-репозитория)
- [Что создаётся по умолчанию](#что-создаётся-по-умолчанию)
- [Быстрый старт](#быстрый-старт)
- [Сценарий 1. Одна ВМ](#сценарий-1-одна-вм)
- [Сценарий 2. Несколько ВМ из разных шаблонов](#сценарий-2-несколько-вм-из-разных-шаблонов)
- [Сценарий 3. Стенд Kubernetes](#сценарий-3-стенд-kubernetes)
- [Проверка после первого apply](#проверка-после-первого-apply)
- [Частые проблемы](#частые-проблемы)
- [Полезно знать](#полезно-знать)

## Что нужно

- Сервер Proxmox VE с уже созданными Cloud-Init шаблонами ВМ.
- Машина с Debian 13 (или похожей), на которой будет запускаться Terraform.
- Доступ к Proxmox по API (токен создаётся в [шаге 0](#шаг-0-создать-api-токен-для-terraform)).

Примеры в документе настроены под такой стенд:

| Параметр | Значение |
|---|---|
| Proxmox | `https://10.1.1.20:8006` |
| Узел | `archimedes` |
| Сеть | `10.1.1.0/24` |
| Шлюз и DNS | `10.1.1.1` |
| Провайдер | `bpg/proxmox 0.119.0` |

Подставьте свои значения в `terraform.tfvars`.

## Установка Terraform

Пример для Debian 13.

1. Скачайте архив **Binary download → AMD64** (в примере `terraform_1.17.1_linux_amd64.zip`) со страницы <https://developer.hashicorp.com/terraform/install>.
2. Установите:

```bash
mkdir terraform-proxmox
mv terraform_1.17.1_linux_amd64.zip terraform-proxmox/
cd terraform-proxmox
sudo apt update && sudo apt install -y curl unzip
unzip terraform_1.17.1_linux_amd64.zip
sudo install -m 0755 terraform /usr/local/bin/terraform
```

Вместо `install` можно выполнить `sudo chown root:root terraform && sudo mv terraform /usr/local/bin/`.

3. Проверьте:

```bash
command -v terraform
terraform version
```

## Зеркало и провайдер

### Зеркало Terraform на Yandex

Если реестр `registry.terraform.io` недоступен, используйте зеркало Яндекса. Создайте файл `~/.terraformrc`:

```hcl
provider_installation {
  network_mirror {
    url = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```

### Провайдер для Proxmox

Выбран провайдер [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest): у него больше загрузок в неделю, он популярнее и чаще обновляется. Именно он прописан по умолчанию во всех конфигурациях.

Как выбирать провайдер самостоятельно: откройте <https://registry.terraform.io/>, введите в поиске `proxmox` и сравните популярность и дату последних релизов.

## Структура репозитория

```
proxmox-lab/
├── README.md                  <- этот файл
├── .gitignore
├── 01-one-vm/                 Сценарий 1: одна ВМ из шаблона (ID шаблона — переменная)
├── 02-two-vms/                Сценарий 2: несколько ВМ из разных шаблонов (по умолчанию 2)
└── 03-k8s-lab/                Сценарий 3: стенд Kubernetes (master + 2 worker)
    └── k8s-vendor.yaml        cloud-init файл, копируется на Proxmox вручную
```

В каждой папке одинаковый набор файлов:

| Файл | Назначение |
|---|---|
| `providers.tf` | Подключение к Proxmox. Обычно не меняется |
| `variables.tf` | Все настройки с описаниями и значениями по умолчанию |
| `main.tf` | Сами ВМ (то, что создаётся) |
| `outputs.tf` | Что напечатать после создания (имена, IP) |
| `terraform.tfvars.example` | Образец ваших значений. Копируется в `terraform.tfvars` |

**Каждая папка — независимый проект.** Команды `terraform ...` всегда выполняются внутри нужной папки. Сценарии можно держать одновременно: у них разные ID ВМ и разные IP.

## Что создаётся по умолчанию

| Сценарий | ВМ (ID шаблона) | ID ВМ | IP |
|---|---|---|---|
| 1 | `test-vm-01` (Ubuntu, 11243) | 5001 | 10.1.1.80 |
| 2 | `ubuntu-vm-01` (11243), `debian-vm-01` (10133) | 5101, 5102 | 10.1.1.81, 10.1.1.82 |
| 3 | `k8s-master`, `k8s-worker1`, `k8s-worker2` (11243) | 5201–5203 | 10.1.1.90, 10.1.1.91, 10.1.1.92 |

Все ВМ создаются **остановленными**. Запускайте их сами: кнопка Start в веб-интерфейсе или `qm start <ID>` на Proxmox.

---

## Быстрый старт

### Шаг 0. Создать API-токен для Terraform

Выполняется один раз на сервере Proxmox (консоль или SSH под root):

```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve tf --privsep 0
```

Последняя команда покажет `value` — секрет токена. Он виден **только один раз**. Полный токен выглядит так:

```
terraform@pve!tf=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Если пользователь `terraform@pve` уже существует, пропустите первую команду.

> Роль `Administrator` выбрана ради простоты домашней лаборатории. В рабочей среде создайте отдельную роль с минимально необходимыми правами.

### Шаг 1. Настроить сценарий

```bash
cd proxmox-lab/01-one-vm            # или 02-two-vms, или 03-k8s-lab
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars               # впишите токен, при желании свои ID и IP
```

Токен можно не хранить в файле, а передать через переменную окружения (безопаснее):

```bash
export TF_VAR_pm_api_token='terraform@pve!tf=СЕКРЕТ'
```

В этом случае удалите строку `pm_api_token` из `terraform.tfvars`.

### Шаг 2. Четыре команды Terraform

```bash
terraform init       # один раз на папку: скачивает провайдер
terraform plan       # показывает, что будет сделано, ничего не меняя
terraform apply      # создаёт ресурсы (спросит подтверждение: введите yes)
terraform destroy    # удаляет всё, что создал этот проект (шаблоны не трогает)
```

> **Привычка №1:** всегда читайте вывод `plan`. Ожидаемо: сценарий 1 — `1 to add`, сценарий 2 — `2 to add`, сценарий 3 — `3 to add`.

---

## Сценарий 1. Одна ВМ

Папка `01-one-vm`. В `terraform.tfvars` меняются:

- `template_id` — ID шаблона;
- `vm_id` — ID новой ВМ;
- `vm_name` — имя;
- `vm_ip` — IP-адрес.

Для шаблона CentOS 10 (ID 180103) обязательно задайте `cpu_type = "x86-64-v3"`.

## Сценарий 2. Несколько ВМ из разных шаблонов

Папка `02-two-vms`. Переменная `vms` — это словарь, одна запись соответствует одной ВМ:

```hcl
vms = {
  "ubuntu-vm-01" = { template_id = 11243, vm_id = 5101, ip = "10.1.1.81/24" }
  ...
}
```

Чтобы получить три машины, добавьте ещё одну запись (образец с CentOS закомментирован в `terraform.tfvars.example`). Код `main.tf` менять не нужно.

## Сценарий 3. Стенд Kubernetes

Папка `03-k8s-lab`: master и два worker. Работает только с шаблоном на **Debian/Ubuntu** (используется `apt`). CentOS не подойдёт.

### 3.1. Положить cloud-init файл на Proxmox

Выполняется один раз, **до** `terraform apply`:

```bash
cd proxmox-lab/03-k8s-lab
scp k8s-vendor.yaml root@10.1.1.20:/var/lib/vz/snippets/
```

Каталог `/var/lib/vz/snippets/` уже существует, если ваши скрипты шаблонов пишут snippets на хранилище `local`.

### 3.2. Создать ВМ

```bash
cp terraform.tfvars.example terraform.tfvars   # впишите токен
terraform init
terraform plan
terraform apply
```

### 3.3. Запустить три ВМ и дождаться cloud-init

Запустите ВМ вручную и подождите 3–7 минут: cloud-init скачивает и устанавливает Kubernetes. На каждом узле проверьте:

```bash
ssh la@10.1.1.90
cloud-init status --wait        # дождаться "status: done"
ls /var/lib/k8s-node-ready      # файл должен существовать
kubeadm version
```

Если что-то пошло не так:

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
```

### 3.4. Создать кластер

На **master** (10.1.1.90):

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
kubectl get nodes        # через 1–2 минуты все 3 узла в статусе Ready
kubectl create deployment nginx --image=nginx --replicas=2
kubectl get pods -o wide
```

Версия Kubernetes задаётся в `k8s-vendor.yaml` (две строки `v1.36`). Чтобы пересоздать стенд: `terraform destroy`, затем `terraform apply`.

---

## Проверка после первого `apply`

1. Выполните `terraform plan` ещё раз. Ожидаемый результат: `No changes`. Если Terraform хочет «исправить» только что созданные ВМ, не применяйте изменения, сначала разберитесь в выводе.
2. На Proxmox выполните `qm config <ID новой ВМ>` и сравните с `qm config <ID шаблона>`. Параметры `bios`, `machine`, `cpu`, `scsi0`, `scsi1` (cloudinit), `efidisk0`, `ciuser`, `sshkeys` должны совпадать с шаблоном. Различаться должны имя, ядра, память и `ipconfig0`.
3. После первого запуска ВМ проверьте вход: `ssh la@<IP>`.

## Частые проблемы

| Симптом | Что делать |
|---|---|
| `401` / `permission denied` | Проверьте токен целиком (`user@realm!имя=секрет`) и что он создан с `--privsep 0` |
| `x509: certificate ...` | Укажите в `terraform.tfvars` `pm_insecure = true` (по умолчанию уже так) |
| `VM ... already exists` | Выбранный `vm_id` занят. Поменяйте его на свободный |
| `can't lock file ... timeout` при клонировании | Несколько клонов одного шаблона мешают друг другу. Запустите `terraform apply -parallelism=1` |
| Сценарий 3: `snippets ... does not exist` | Не выполнен шаг 3.1 (`scp`) |
| ВМ с CentOS 10 не загружается | В сценариях 1 и 2 для неё нужен `cpu_type = "x86-64-v3"` |
| Сценарий 3: нет интернета на узле | Проверьте `gateway` и `dns_servers`: cloud-init скачивает пакеты из интернета |
| Не удаётся войти по SSH | Используйте ключ, публичная часть которого лежит в `/root/configs/authorized_keys` на Proxmox: `ssh -i ~/.ssh/id_ed25519 la@IP` |

## Полезно знать

- Файл `terraform.tfstate` в папке сценария — «память» Terraform о созданном. Не удаляйте и не публикуйте его. `terraform.tfvars` тоже не публикуйте (оба файла уже добавлены в `.gitignore`).
- Если удалить ВМ, созданную Terraform, вручную в Proxmox, то `terraform apply` создаст её заново.
- Изменили `main.tf` или переменные: выполните `terraform plan`, затем `terraform apply`. Для смены CPU и RAM у запущенной ВМ потребуется перезапуск.
- Хэш пароля и SSH-ключ пользователя `la` берутся из шаблона (см. скрипты создания шаблонов). Terraform их не меняет.
