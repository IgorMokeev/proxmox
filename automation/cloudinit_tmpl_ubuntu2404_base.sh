#!/bin/bash
# ==============================================================================
# Script:  cloudinit_tmpl_ubuntu2404_base.sh
# Author:  Igor Mokeev
# Purpose: Упрощенная (base) версия создания Proxmox-шаблона 
#          Cloud-Init Ubuntu Noble (24.04 LTS).
# ==============================================================================
#
# ОПИСАНИЕ:
# Скрипт автоматизирует создание шаблона виртуальной машины в Proxmox VE 
# на основе официального cloud-образа Ubuntu 24.04. Данная "base" версия 
# оптимизирована для простоты и надежности за счет использования стандартных 
# хранилищ Proxmox по умолчанию.
#
# ТРЕБОВАНИЯ И ПОДГОТОВКА:
# 1. Скачайте актуальный cloud-образ Ubuntu в директорию /root:
#    wget -b https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
# 2. Переименуйте скачанный файл в формат .qcow2:
#    mv noble-server-cloudimg-amd64.img noble-server-cloudimg-amd64.qcow2
# 3. Сгенерируйте SSH-ключи (если еще не созданы) и поместите данные публичного ключа 
#    в файл: /root/configs/authorized_keys
#
# НАСТРОЙКА ПАРОЛЯ ПОЛЬЗОВАТЕЛЯ (Cloud-Init):
# Пароль главного пользователя можно задать одним из следующих способов:
# Хэш из защищенного файла:
#   CI_PASSWORD_HASH=$(cat /root/configs/cipass.hash)
#   (Файл должен иметь права доступа 600: chmod 600 /root/configs/cipass.hash)
# Генерация собственного хэша:
#   Выполните в CLI Proxmox: openssl passwd -6 'Ваш_Надежный_Пароль'
#   Скопируйте вывод и вставьте его в переменную CI_PASSWORD_HASH внутри скрипта.
# Жесткое кодирование в скрипте (Не рекомендуется для продакшена):
#   qm set $VMID --cipassword 'Pa$$w0rd'
# Значение по умолчанию:
#   Используется предустановленный хэш для пароля 'Pa$$w0rd'.
#
# ОГРАНИЧЕНИЯ (Осознанные, ради простоты и скорости):
#   - Диски ВМ и шаблоны создаются ТОЛЬКО на хранилище 'local-lvm'.
#   - Файлы snippets (cloud-init) сохраняются ТОЛЬКО на хранилище 'local'.
#   - Не требуется выбор типа хранилища, формата диска (raw/qcow2) 
#     или формата EFI-диска (на LVM-thin всё работает из коробки).
#   * Если вам требуется использование внешних или нестандартных хранилищ, 
#     воспользуйтесь "ext" версией данного скрипта (учтите, что скорость 
#     операций на внешних хранилищах может быть значительно ниже).
#
# ИСПОЛЬЗОВАНИЕ:
#   ./cloudinit_tmpl_ubuntu2404_base.sh            # Интерактивный режим (с запросами)
#   ./cloudinit_tmpl_ubuntu2404_base.sh --default  # Автоматический режим (все параметры по умолчанию)
#
# ==============================================================================

# Жёсткий режим: ошибка / неустановленная переменная / ошибка пайпа — выход
set -euo pipefail

# ============================================================
# НАСТРОЙКИ (при необходимости правьте здесь)
# ============================================================

# Хранилища (фиксированы)
readonly DISK_STORAGE="local-lvm"
readonly SNIPPET_STORAGE="local"

# Идентификация шаблона
readonly TEMPLATE_ID=11243
readonly TEMPLATE_NAME="ubuntu24cloud-tmpl"

# Железо
readonly RAM_MB="4096"
readonly CPU_CORES="2"
readonly CPU_TYPE="x86-64-v2-AES"
readonly OS_TYPE="l26"              # l26 = Linux 7.x - 2.6 Kernel
readonly MACHINE_TYPE="q35"
# BIOS: ovmf = UEFI (рекомендуется), seabios = Legacy BIOS
readonly BIOS_TYPE="ovmf"

# Cloud-init параметры
readonly CI_USERNAME="r00t"
readonly CI_TIMEZONE="Europe/Moscow"
readonly SNIPPET_YAML="cloud-noble-server.yaml"

# Пароль главного пользователя (хэш SHA-512)
# Сгенерировать: openssl passwd -6 'Pa$$w0rd'
readonly CI_PASS_HASH='$6$wBxZDyxv8VMoDBLY$ty9jnprnDcxS8LVQkWO4gePNOSEb.eGsezN7HYMIITSute6BWObZy9oOQtDBPrM3nHbx54Mn8rqkmTVtFrtoj0'

# Пути
readonly IMAGE_DIR="/root"
readonly IMAGE_NAME="noble-server-cloudimg-amd64.qcow2"
readonly SSH_KEYS_PATH="/root/configs/authorized_keys"

# Сетевые настройки
readonly NET_BRIDGE="vmbr0"
readonly NET_FIREWALL="1"

# Размер диска (прирост, GB)
readonly DISK_GROW_GB="20"

# ============================================================
# РАБОЧИЕ ПЕРЕМЕННЫЕ (меняются через меню)
# ============================================================
template_id="$TEMPLATE_ID"
template_name="$TEMPLATE_NAME"
ram_mb="$RAM_MB"
bios_type="$BIOS_TYPE"
ci_username="$CI_USERNAME"
snippet_dir=""        # вычисляется в preflight_checks

# ============================================================
# HELPER ФУНКЦИИ
# ============================================================

log_info()  { echo "ℹ️  $*"; }
log_ok()    { echo "✅ $*"; }
log_warn()  { echo "⚠️  $*"; }
log_error() { echo "❌ $*"; }

ask() {
    local prompt="$1"
    local default="$2"
    local value
    read -r -p "$prompt [$default]: " value
    echo "${value:-$default}"
}

# ============================================================
# PREFLIGHT CHECKS
# ============================================================

preflight_checks() {
    log_info "Предварительные проверки..."

    local image_path="${IMAGE_DIR}/${IMAGE_NAME}"
    local probe=""

    # 1. Root
    if [[ $EUID -ne 0 ]]; then
        log_error "Запустите скрипт от имени root."
        exit 1
    fi

    # 2. Валидность ввода
    if [[ ! "$template_id" =~ ^[0-9]+$ ]]; then
        log_error "VM ID должен быть числом, получено: '${template_id}'"
        exit 1
    fi
    if [[ ! "$ram_mb" =~ ^[0-9]+$ ]]; then
        log_error "RAM (MB) должна быть числом, получено: '${ram_mb}'"
        exit 1
    fi
    if [[ "$bios_type" != "ovmf" && "$bios_type" != "seabios" ]]; then
        log_error "BIOS должен быть 'ovmf' или 'seabios', получено: '${bios_type}'"
        exit 1
    fi

    # 3. Образ
    if [[ ! -f "$image_path" ]]; then
        log_error "Образ не найден: ${image_path}"
        echo "Скачайте: wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
        echo "Переименуйте: mv noble-server-cloudimg-amd64.img ${IMAGE_NAME}"
        exit 1
    fi
    log_ok "Образ найден: ${image_path}"

    # 4. SSH ключи (не критично)
    if [[ -f "$SSH_KEYS_PATH" ]]; then
        log_ok "SSH-ключи найдены."
    else
        log_warn "SSH-ключи не найдены: ${SSH_KEYS_PATH}"
        log_warn "Cloud-init не сможет добавить ваш ключ."
    fi

    # 5. VMID не занят
    if qm status "$template_id" &>/dev/null; then
        log_error "VM ${template_id} уже существует. Выберите другой ID."
        exit 1
    fi
    log_ok "VM ID ${template_id} свободен."

    # 6. Директория snippets на local доступна
    #    (pvesm path требует полный том snippets/<файл>, просим пробный файл)
    probe="$(pvesm path "${SNIPPET_STORAGE}:snippets/.probe" 2>/dev/null || true)"
    if [[ -n "$probe" ]]; then
        snippet_dir="$(dirname "$probe")"
    fi
    if [[ -z "$snippet_dir" || ! -d "$snippet_dir" ]]; then
        cat <<ERR
==========================================================
❌ На хранилище '${SNIPPET_STORAGE}' не включён тип контента Snippets!
----------------------------------------------------------
Выполните в GUI Proxmox:
  1. Datacenter -> Storage -> ${SNIPPET_STORAGE} -> Edit
  2. В поле 'Content' добавьте 'Snippets'.
  3. Сохраните и запустите скрипт повторно.
==========================================================
ERR
        exit 1
    fi
    log_ok "Snippets-директория: ${snippet_dir}"
}

# ============================================================
# СОЗДАНИЕ VENDOR-СНИППЕТА
# ============================================================

create_snippet_yaml() {
    local snippet_file="${snippet_dir}/${SNIPPET_YAML}"
    log_info "Создание vendor-snippet: ${snippet_file}..."

    cat > "$snippet_file" <<EOF
#cloud-config
# Единый vendor-data для cloud-init шаблона

# Часовой пояс (в образе Ubuntu по умолчанию UTC)
timezone: ${CI_TIMEZONE}

# Установка qemu-guest-agent при первом старте каждого клона
runcmd:
  - apt-get update
  - apt-get install -y qemu-guest-agent
  - systemctl enable --now qemu-guest-agent
EOF

    log_ok "Snippet создан."
}

# ============================================================
# СОЗДАНИЕ ВМ И ШАБЛОНА
# ============================================================

create_template() {
    log_info "Начало создания шаблона VM ${template_id} (${template_name})..."
    local image_path="${IMAGE_DIR}/${IMAGE_NAME}"

    # 1. Базовая ВМ
    log_info "Создание базовой ВМ (BIOS: ${bios_type})..."
    qm create "$template_id" \
      --name "$template_name" \
      --memory "$ram_mb" \
      --cores "$CPU_CORES" \
      --cpu "$CPU_TYPE" \
      --net0 "virtio,bridge=${NET_BRIDGE},firewall=${NET_FIREWALL}" \
      --machine "$MACHINE_TYPE" \
      --ostype "$OS_TYPE" \
      --bios "$bios_type" \
      --scsihw virtio-scsi-single \
      --serial0 socket \
      --vga serial0 \
      --agent enabled=1

    # 2. EFI-диск только для UEFI (на lvm-thin формат не важен — снапшоты
    #    делает само хранилище)
    if [[ "$bios_type" == "ovmf" ]]; then
        log_info "Настройка UEFI: создание EFI-диска..."
        qm set "$template_id" --efidisk0 "${DISK_STORAGE}:1,efitype=4m,ms-cert=2023k,pre-enrolled-keys=1"
    else
        log_warn "Выбран Legacy BIOS (seabios): EFI-диск не создаётся."
    fi

    # 3. CD-ROM (опционально, для отладки)
    qm set "$template_id" --ide2 none,media=cdrom

    # 4. Импорт образа
    log_info "Импорт диска..."
    qm importdisk "$template_id" "$image_path" "$DISK_STORAGE"

    # 5. Подключение импортированного диска как scsi0.
    #    Имя тома читаем из ключа unused0 конфига — надёжно при любом BIOS
    #    (с efidisk и без).
    local imported_vol
    imported_vol="$(qm config "$template_id" | sed -n 's/^unused0: //p')"
    if [[ -z "$imported_vol" ]]; then
        log_error "Не удалось определить импортированный диск (unused0 не найден в конфиге)."
        exit 1
    fi
    log_info "Импортированный том: ${imported_vol}"
    qm set "$template_id" --scsi0 "${imported_vol},discard=on,ssd=1,iothread=1"

    # 6. Порядок загрузки
    qm set "$template_id" --boot order=scsi0

    # 7. Cloud-Init диск
    qm set "$template_id" --scsi1 "${DISK_STORAGE}:cloudinit"

    # 8. Расширение диска
    log_info "Расширение диска на +${DISK_GROW_GB}G..."
    qm resize "$template_id" scsi0 "+${DISK_GROW_GB}G"

    # 9. Cloud-Init параметры
    log_info "Настройка Cloud-Init..."
    qm set "$template_id" --ciuser "$ci_username"
    qm set "$template_id" --cipassword "$CI_PASS_HASH"
    qm set "$template_id" --ciupgrade 0
    qm set "$template_id" --ipconfig0 ip=dhcp
    qm set "$template_id" --sshkeys "$SSH_KEYS_PATH"
    qm set "$template_id" --cicustom "vendor=${SNIPPET_STORAGE}:snippets/${SNIPPET_YAML}"

    # 10. Превращение в шаблон
    log_info "Конвертация в шаблон..."
    qm template "$template_id"

    log_ok "Шаблон '${template_name}' (ID: ${template_id}) успешно создан! (BIOS: ${bios_type})"
    echo ""
    echo "Следующие шаги:"
    echo "  клонирование:  qm clone ${template_id} <NEWID> --name <hostname> --full"
    echo "  запуск клона:  qm start <NEWID>"
}

# ============================================================
# ИНТЕРАКТИВНОЕ МЕНЮ
# ============================================================

show_summary() {
    cat <<SUMMARY

========================================
  Итоговые параметры шаблона
========================================
  VM ID:        ${template_id}
  Имя:          ${template_name}
  RAM:          ${ram_mb} MB
  BIOS:         ${bios_type} $([ "$bios_type" == "ovmf" ] && echo "(UEFI)" || echo "(Legacy)")
  Disk storage: ${DISK_STORAGE} (фиксировано)
  CI user:      ${ci_username}
  Snippets:     ${SNIPPET_STORAGE} (фиксировано)
  Образ:        ${IMAGE_DIR}/${IMAGE_NAME}
========================================

SUMMARY
}

interactive_config() {
    cat <<MENU

========================================
  Настройка параметров шаблона
  (ENTER = значение по умолчанию)
========================================

MENU

    template_id="$(ask "VM ID шаблона" "$template_id")"
    template_name="$(ask "Имя шаблона" "$template_name")"
    ram_mb="$(ask "RAM (MB)" "$ram_mb")"
    bios_type="$(ask "BIOS (ovmf=UEFI / seabios=Legacy)" "$bios_type")"
    ci_username="$(ask "Имя пользователя (Cloud-Init)" "$ci_username")"

    log_ok "Параметры настроены."
    show_summary
}

main_menu() {
    cat <<MENU

========================================
  Proxmox Ubuntu 24.04 Cloud-Init Template
  (light: диски только на local-lvm)
========================================
  1) Создать с настройками по умолчанию
  2) Настроить вручную
  3) Выход
========================================

MENU

    read -r -p "Выберите опцию: " choice
    case "$choice" in
        1) log_info "Запуск с настройками по умолчанию..."
           show_summary ;;
        2) interactive_config ;;
        3) log_info "Выход."; exit 0 ;;
        *) log_error "Неверный выбор."; exit 1 ;;
    esac
}

# ============================================================
# ГЛАВНАЯ ТОЧКА ВХОДА
# ============================================================

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Запустите скрипт от имени root."
        exit 1
    fi

    if [[ $# -eq 0 ]]; then
        main_menu
    elif [[ "${1:-}" != "--default" ]]; then
        echo "Использование: $0 [--default]"
        exit 1
    fi

    preflight_checks
    create_snippet_yaml
    create_template
}

main "$@"
