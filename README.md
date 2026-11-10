<div align="center">

# 🖥️ Proxmox Home Lab

**Учебный проект по автоматизации домашней лаборатории на Proxmox VE 9**

Cloud-Init шаблоны → Terraform → Ansible: от первой ВМ до готового стенда

![Proxmox VE](https://img.shields.io/badge/Proxmox%20VE-9.x-E57000?logo=proxmox&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-Cloud--Init-4EAA25?logo=gnubash&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-bpg%2Fproxmox-844FBA?logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-planned-EE0000?logo=ansible&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20progress-blue)

</div>

---

## 📖 О проекте

Этот репозиторий создан **для обучения в домашней лаборатории на Proxmox VE версии 9**. Здесь собраны готовые к использованию примеры и пошаговые шпаргалки, которые показывают, как перейти от ручного создания виртуальных машин в веб-интерфейсе к воспроизводимой автоматизации.

Идея простая: сначала делаем **шаблоны ВМ**, затем **описываем инфраструктуру кодом**, а потом **настраиваем машины автоматически**.

```
 Cloud-образ  ──►  Шаблон Proxmox  ──►  ВМ через Terraform  ──►  Настройка через Ansible
  (скрипты)         (Cloud-Init)          (стенды как код)            (в планах)
```

## 🎯 Для кого

- Для тех, кто поднял домашний Proxmox и хочет перестать создавать ВМ вручную.
- Для начинающих в Infrastructure as Code: примеры короткие, с комментариями и разбором частых ошибок.
- Для самостоятельной подготовки к работе с DevOps-инструментами на безопасном стенде.

## 🧩 Что внутри

| Раздел | Что это | Статус |
|---|---|---|
| [`automation/`](automation/README.md) | Bash-скрипты создания Cloud-Init шаблонов Proxmox для разных ОС | ✅ Готово |
| [`automation/terraform-proxmox/`](automation/terraform-proxmox/README.md) | Обучающие сценарии Terraform: одна ВМ, несколько ВМ, стенд Kubernetes | ✅ Готово |
| `ansible/` | Обучение по Ansible: настройка ВМ, роли, плейбуки | 🛠️ В планах |

### 1. Cloud-Init шаблоны

Скрипты автоматически создают шаблоны ВМ из официальных cloud-образов: с настроенным пользователем, SSH-ключами, сетью по DHCP и `qemu-guest-agent`.

Поддерживаемые ОС:

- Ubuntu 24.04 LTS (версии `base` и `ext`)
- Debian 13
- CentOS 10
- ALT 11
- Astra Linux 1.7.10 (GUI)

Версия `base` работает со стандартным хранилищем `local-lvm`, версия `ext` рассчитана на внешние и нестандартные хранилища.

👉 [Подробнее в automation/README.md](automation/README.md)

### 2. Terraform

Три учебных сценария на провайдере [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest), каждый из которых независимый проект:

| Сценарий | Что создаёт |
|---|---|
| `01-one-vm` | Одну ВМ из выбранного шаблона |
| `02-two-vms` | Несколько ВМ из разных шаблонов |
| `03-k8s-lab` | Стенд Kubernetes: master + 2 worker |

👉 [Подробнее в automation/terraform-proxmox/README.md](automation/terraform-proxmox/README.md)

### 3. Ansible (в планах)

Следующий этап обучения: автоматическая настройка уже созданных машин. Планируется разобрать инвентарь, плейбуки, роли и подготовку стенда Kubernetes средствами Ansible.

## 🗺️ Дорожная карта

- [x] Скрипты создания Cloud-Init шаблонов для Proxmox
- [x] Шаблоны для нескольких ОС (Ubuntu, Debian, CentOS, ALT, Astra)
- [x] Terraform: одна ВМ
- [x] Terraform: несколько ВМ из разных шаблонов
- [x] Terraform: стенд Kubernetes
- [ ] Ansible: основы и инвентарь
- [ ] Ansible: плейбуки и роли для типовых задач
- [ ] Ansible: развёртывание Kubernetes

## 🚀 Быстрый старт

Рекомендуемый порядок изучения:

1. **Создайте шаблон.** Подготовьте образ и SSH-ключ, запустите скрипт из [`automation/`](automation/README.md):
   ```bash
   ./cloudinit_tmpl_ubuntu2404_base.sh --default
   ```
2. **Установите Terraform** и создайте API-токен Proxmox по инструкции из [`terraform-proxmox`](automation/terraform-proxmox/README.md).
3. **Поднимите первую ВМ** из шаблона сценарием `01-one-vm`:
   ```bash
   cd automation/terraform-proxmox/01-one-vm
   cp terraform.tfvars.example terraform.tfvars
   terraform init && terraform plan && terraform apply
   ```
4. **Переходите к сложным стендам:** `02-two-vms`, затем `03-k8s-lab`.

## 📁 Структура репозитория

```
proxmox/
├── README.md                          <- вы здесь
└── automation/
    ├── README.md                      описание скриптов шаблонов
    ├── cloudinit_tmpl_alt11_base.sh
    ├── cloudinit_tmpl_astra1710gui_base.sh
    ├── cloudinit_tmpl_centos10_base.sh
    ├── cloudinit_tmpl_debian13_base.sh
    ├── cloudinit_tmpl_ubuntu2404_base.sh
    ├── cloudinit_tmpl_ubuntu2404_ext.sh
    └── terraform-proxmox/
        ├── README.md                  шпаргалка по Terraform + Proxmox
        ├── 01-one-vm/
        ├── 02-two-vms/
        └── 03-k8s-lab/
```

## ⚙️ Требования

- **Proxmox VE 9.x** (домашняя лаборатория или тестовый сервер).
- Доступ к серверу Proxmox по SSH под `root` для скриптов шаблонов.
- Машина с Linux (в примерах Debian 13) для запуска Terraform.
- Доступ в интернет для скачивания cloud-образов, провайдеров и пакетов.

## ⚠️ Важно

- Проект **учебный** и рассчитан на домашнюю лабораторию. Не используйте его настройки в рабочей среде без доработки.
- В примерах для простоты используется роль `Administrator` для токена Terraform и тестовый пароль пользователя в шаблонах. Перед любым другим применением смените пароль и ограничьте права токена.
- Не публикуйте файлы `terraform.tfstate`, `terraform.tfvars`, хэши паролей и приватные SSH-ключи.
- Конфиги написаны по документации провайдеров. После первого запуска сверяйте результат с чек-листом из README каждого раздела.

## 👤 Автор

**Igor Mokeev** — [github.com/IgorMokeev](https://github.com/IgorMokeev)

## 🤝 Обратная связь

Нашли ошибку или хотите предложить улучшение? Создайте issue или pull request. Идеи для новых шаблонов ОС и учебных стендов приветствуются.

---

<div align="center">

⭐ Если проект оказался полезным, поставьте звезду репозиторию

</div>
