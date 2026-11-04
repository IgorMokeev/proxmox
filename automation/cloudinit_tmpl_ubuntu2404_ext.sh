#!/bin/bash
# ==============================================================================
# Script:  cloudinit_tmpl_ubuntu2404_ext.sh
# Author:  Igor Mokeev / https://github.com/IgorMokeev
# Date:    04.11.2026
# Purpose: Extended (ext) версия создания Proxmox-шаблона 
#          Cloud-Init Ubuntu Noble (24.04 LTS).
# ==============================================================================
#
# ОПИСАНИЕ:
# Скрипт автоматизирует создание шаблона виртуальной машины в Proxmox VE 
# на основе официального cloud-образа Ubuntu 24.04. Данная "ext" версия
# поддерживает создание шаблонов и vm на внешних хранилищах proxmox.
# Скорость клонирования и время запуска ВМ зависят от характеристик
# сети и дисковой подсистемы. Длительная активация ВМ после клонирования 
# свидетельствует о нехватке пропускной способности сети или низкой скорости 
# внешнего хранилища.
#
# ТРЕБОВАНИЯ И ПОДГОТОВКА:
# 1. Скачайте актуальный cloud-образ Ubuntu в директорию /root:
#    wget -b https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
# 2. Переименуйте скачанный файл в формат .qcow2:
#    mv noble-server-cloudimg-amd64.img noble-server-cloudimg-amd64.qcow2
# 3. ОБЯЗАТЕЛЬНО: сгенерируйте SSH-ключи (если еще не созданы) и поместите 
#    данные публичного ключа в файл: /root/configs/authorized_keys
#    Если файл отсутствует или пуст — скрипт завершится с ошибкой.
#
# НАСТРОЙКА ПОЛЬЗОВАТЕЛЯ (Cloud-Init):
# Пользователь по умолчанию - la (local admin)
# Пароль в VM по умолчанию - Pa$$w0rd
# Чтобы задать свой пароль, сгенерируйте хэш SHA-512 и подставьте его
# в переменную CI_PASS_HASH в разделе НАСТРОЙКИ (значение в одинарных кавычках):
#   1. Выполните в CLI Proxmox: openssl passwd -6 'Ваш_Надежный_Пароль'
#   2. Скопируйте вывод целиком (начинается с $6$...) и вставьте его:
#        CI_PASS_HASH='$6$...ваш_хэш...'
#   Одинарные кавычки обязательны, иначе bash раскроет символы $ в хэше.
#
# Альтернативный способ (рекомендуется, не светит хэш в скрипте):
# положите хэш в файл /root/configs/cipass.hash и выставьте права:
#   chmod 600 /root/configs/cipass.hash
# Если файл существует и не пуст, он имеет приоритет над CI_PASS_HASH.
#
# ВАЖНО: про формат дисков на файловых хранилищах
# -------------------------------------------------
# Для хранилищ типа dir / nfs / cifs / cephfs (например, "smb_share", local)
# по умолчанию Proxmox создаёт RAW-диски, которые НЕ ПОДДЕРЖИВАЮТ
# снапшоты ВМ. Чтобы снапшоты работали — нужен формат qcow2.
# Этот скрипт автоматически:
#   1) ставит qcow2 для основного диска при импорте (DISK_FORMAT=auto);
#   2) ставит qcow2 для EFI-диска (иначе снапшоты блокируются целиком).
# Переопределить формат основного диска можно через DISK_FORMAT.
#
# Для блочных хранилищ (lvm-thin, zfspool, rbd) формат не нужен —
# снапшоты работают на уровне самого хранилища.
# -------------------------------------------------
#
# ВАЖНО: про кластер и snippets
# -------------------------------------------------
# Vendor-snippet (cloud-init) хранится файлом на хранилище snippets.
# Если это локальное хранилище ('local'), файл существует только на одной
# ноде кластера, и клон, запущенный на другой ноде, не стартует.
# В кластере укажите для snippets общее хранилище (NFS/CIFS с включённым
# типом контента Snippets) либо скопируйте файл на каждую ноду.
# -------------------------------------------------
#
#   * Если вам требуется простая установка в стандартные proxmox хранилища
#     лучше воспользуйтесь "base" версией данного скрипта
#
# ИСПОЛЬЗОВАНИЕ:
#   ./cloudinit_tmpl_ubuntu2404_ext.sh            # Интерактивный режим (с запросами)
#   ./cloudinit_tmpl_ubuntu2404_ext.sh --default  # Автоматический режим (все параметры по умолчанию)
#
# ==============================================================================

# Жёсткий режим: ошибка / неустановленная переменная / ошибка пайпа — выход
# -E: ERR/EXIT-ловушки наследуются функциями
set -Eeuo pipefail

# ============================================================
# НАСТРОЙКИ (при необходимости правьте здесь)
# ============================================================

# Хранилища
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
readonly CI_USERNAME="la"
readonly CI_TIMEZONE="Europe/Moscow"
readonly SNIPPET_YAML="cloud-noble-server.yaml"

# Пароль главного пользователя (хэш SHA-512)
# Сгенерировать: openssl passwd -6 'Pa$$w0rd'
# (не readonly: может быть переопределён из файла CI_PASS_FILE)
CI_PASS_HASH='$6$wBxZDyxv8VMoDBLY$ty9jnprnDcxS8LVQkWO4gePNOSEb.eGsezN7HYMIITSute6BWObZy9oOQtDBPrM3nHbx54Mn8rqkmTVtFrtoj0'
readonly CI_PASS_FILE="/root/configs/cipass.hash"

# Пути
readonly IMAGE_DIR="/root"
readonly IMAGE_NAME="noble-server-cloudimg-amd64.qcow2"
readonly SSH_KEYS_PATH="/root/configs/authorized_keys"

# Сетевые настройки
readonly NET_BRIDGE="vmbr0"
readonly NET_FIREWALL="1"

# Размер диска (прирост, GB)
readonly DISK_GROW_GB="10"

# Формат основного диска: auto | raw | qcow2
#   auto   = qcow2 для файловых хранилищ (dir/nfs/cifs/cephfs), raw для блочных
#   raw    = всегда raw (снапшоты ВМ НЕ будут работать на dir/nfs/cifs!)
#   qcow2  = всегда qcow2 (работает везде, но медленнее на lvm-thin/zfs)
readonly DISK_FORMAT="auto"

# ============================================================
# ТЕКУЩИЕ РАБОЧИЕ ПЕРЕМЕННЫЕ (могут меняться интерактивно)
# ============================================================
template_id="$TEMPLATE_ID"
template_name="$TEMPLATE_NAME"
ram_mb="$RAM_MB"
bios_type="$BIOS_TYPE"
disk_storage="$DISK_STORAGE"
ci_username="$CI_USERNAME"
snippet_storage="$SNIPPET_STORAGE"
image_dir="$IMAGE_DIR"
image_name="$IMAGE_NAME"
snippet_dir=""        # вычисляется в preflight_checks
disk_format="$DISK_FORMAT"
vm_created=0          # 1 = ВМ создана, но шаблон ещё не готов (для отката)

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

# Откат: если скрипт завершился с ошибкой после qm create — удаляем
# недособранную ВМ, чтобы повторный запуск не упирался в "VM уже существует".
cleanup_on_exit() {
    local rc=$?
    if [[ $rc -ne 0 && "$vm_created" == "1" ]]; then
        log_warn "Ошибка (код ${rc}) — удаляю недособранную ВМ ${template_id}..."
        qm destroy "$template_id" --purge --destroy-unreferenced-disks 1 \
            || log_warn "Не удалось удалить ВМ ${template_id}, удалите вручную: qm destroy ${template_id} --purge"
    fi
    exit "$rc"
}
trap cleanup_on_exit EXIT

# Проверяет, что хранилище существует и поддерживает тип контента.
# Вывод сначала собирается в переменную: grep -q в пайпе под pipefail
# может дать ложную ошибку из-за SIGPIPE.
storage_has_content() {
    local storage="$1"
    local content="$2"
    local list
    list="$(pvesm status --content "$content" 2>/dev/null | awk 'NR>1 {print $1}')" || true
    grep -qx "$storage" <<<"$list"
}

# Вычисляет директорию snippets для любого файлового хранилища.
get_snippet_dir() {
    local storage="$1"
    local probe_path
    if ! probe_path="$(pvesm path "${storage}:snippets/.snippet_probe" 2>/dev/null)"; then
        echo ""
        return 0
    fi
    dirname "$probe_path"
}

# Определяет тип плагина хранилища (dir, lvmthin, nfs, cifs, zfspool и т.д.)
get_storage_type() {
    local storage="$1"
    pvesm status 2>/dev/null | awk -v s="$storage" '$1 == s {print $2; exit}'
}

# Решает, какой формат ОС-диска использовать при импорте.
# Возвращает в STDOUT ТОЛЬКО формат (или пустую строку).
# Все логи идут в STDERR, чтобы не ломать захват результата через $(...).
resolve_disk_format() {
    local format="$1"
    local storage="$2"

    if [[ "$format" != "auto" ]]; then
        echo "$format"
        return 0
    fi

    local stype
    stype="$(get_storage_type "$storage")"
    case "$stype" in
        dir|nfs|cifs|cephfs|btrfs|glusterfs)
            # Файловые хранилища: raw не умеет снапшоты ВМ → используем qcow2
            log_info "Хранилище '${storage}' — файловое (${stype}), формат ОС-диска: qcow2" >&2
            echo "qcow2"
            ;;
        lvmthin|zfspool|rbd|iscsi|lvm|drbd)
            # Блочные хранилища: формат не нужен, снапшоты на уровне хранилища
            log_info "Хранилище '${storage}' — блочное (${stype}), формат ОС-диска: raw (по умолчанию)" >&2
            echo ""
            ;;
        "")
            log_warn "Не удалось определить тип хранилища '${storage}', использую raw." >&2
            echo ""
            ;;
        *)
            log_warn "Неизвестный тип хранилища '${stype}' для '${storage}', использую raw." >&2
            echo ""
            ;;
    esac
}

# ============================================================
# PREFLIGHT CHECKS
# ============================================================

preflight_checks() {
    log_info "Предварительные проверки..."

    # ВАЖНО: берём image_dir (может быть изменён интерактивно), а не IMAGE_DIR
    local image_path="${image_dir}/${image_name}"
    local keys_dir
    keys_dir="$(dirname "$SSH_KEYS_PATH")"

    # Root
    if [[ $EUID -ne 0 ]]; then
        log_error "Запустите скрипт от имени root."
        exit 1
    fi

    # SSH-ключи (КРИТИЧНО: без них доступ к клонам невозможен)
    if [[ ! -d "$keys_dir" || ! -s "$SSH_KEYS_PATH" ]]; then
        cat <<ERR
==========================================================
❌ SSH-ключи не найдены: ${SSH_KEYS_PATH}
----------------------------------------------------------
Без публичного ключа скрипт не может создать рабочий шаблон.
Создайте ключи и повторите запуск
Пример:

  1. Сгенерируйте пару ключей (если ещё нет):
       ssh-keygen -t ed25519 -C "proxmox-template"
  2. Создайте директорию и файл с публичным ключом:
       mkdir -p ${keys_dir}
       cat ~/.ssh/id_ed25519.pub >> ${SSH_KEYS_PATH}
       chmod 600 ${SSH_KEYS_PATH}
  3. Запустите скрипт повторно.
==========================================================
ERR
        exit 1
    fi
    log_ok "SSH-ключи найдены: ${SSH_KEYS_PATH}"

    # Хэш пароля: файл (если есть) имеет приоритет над значением в скрипте
    if [[ -s "$CI_PASS_FILE" ]]; then
        local perms
        perms="$(stat -c '%a' "$CI_PASS_FILE")"
        if [[ "$perms" != "600" ]]; then
            log_warn "У ${CI_PASS_FILE} права ${perms}, рекомендуется 600."
        fi
        CI_PASS_HASH="$(tr -d '[:space:]' < "$CI_PASS_FILE")"
        log_ok "Хэш пароля взят из ${CI_PASS_FILE}"
    fi
    if [[ ! "$CI_PASS_HASH" =~ ^\$6\$[^$]+\$[^$]+$ ]]; then
        log_error "CI_PASS_HASH не похож на хэш SHA-512 (ожидается формат \$6\$salt\$hash)."
        exit 1
    fi

    # Валидность ввода
    if [[ ! "$template_id" =~ ^[0-9]+$ ]]; then
        log_error "VM ID должен быть числом, получено: '${template_id}'"
        exit 1
    fi
    if (( template_id < 100 )); then
        log_error "VM ID должен быть >= 100, получено: '${template_id}'"
        exit 1
    fi
    if [[ ! "$template_name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        log_error "Имя шаблона должно быть валидным DNS-именем (буквы, цифры, '-', '.'), получено: '${template_name}'"
        exit 1
    fi
    if [[ ! "$ram_mb" =~ ^[0-9]+$ ]]; then
        log_error "RAM (MB) должна быть числом, получено: '${ram_mb}'"
        exit 1
    fi
    if [[ ! "$ci_username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Недопустимое имя пользователя Cloud-Init: '${ci_username}'"
        exit 1
    fi
    if [[ "$bios_type" != "ovmf" && "$bios_type" != "seabios" ]]; then
        log_error "BIOS должен быть 'ovmf' или 'seabios', получено: '${bios_type}'"
        exit 1
    fi

    # Образ
    if [[ ! -f "$image_path" ]]; then
        log_error "Образ не найден: ${image_path}"
        echo "Скачайте: wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
        echo "Переименуйте: mv noble-server-cloudimg-amd64.img ${image_name}"
        exit 1
    fi
    log_ok "Образ найден: ${image_path}"

    # VMID не занят
    if qm status "$template_id" &>/dev/null; then
        log_error "VM ${template_id} уже существует. Выберите другой ID."
        exit 1
    fi
    log_ok "VM ID ${template_id} свободен."


    # Snippets-хранилище: тип контента
    if ! storage_has_content "$snippet_storage" snippets; then
        cat <<ERR
==========================================================
❌ Для хранилища '${snippet_storage}' не включён тип контента Snippets!
----------------------------------------------------------
Выполните в GUI Proxmox:
  1. Datacenter -> Storage -> ${snippet_storage} -> Edit
  2. В поле 'Content' добавьте 'Snippets'.
  3. Сохраните и запустите скрипт повторно.
==========================================================
ERR
        exit 1
    fi
    log_ok "Хранилище '${snippet_storage}' поддерживает snippets."

    snippet_dir="$(get_snippet_dir "$snippet_storage")"
    if [[ -z "$snippet_dir" || ! -d "$snippet_dir" ]]; then
        log_error "Директория snippets недоступна: '${snippet_dir:-<не определена>}'"
        log_error "Проверьте, что хранилище '${snippet_storage}' смонтировано и активно."
        exit 1
    fi
    log_ok "Snippets-директория: ${snippet_dir}"

    # Кластер + локальное хранилище snippets = клон на другой ноде не стартует
    if [[ -f /etc/pve/corosync.conf && "$(get_storage_type "$snippet_storage")" == "dir" ]]; then
        log_warn "Обнаружен кластер, а snippets лежат на хранилище типа 'dir' (${snippet_storage})."
        log_warn "Если оно не общее для всех нод, клоны на других нодах не запустятся —"
        log_warn "используйте общее хранилище для snippets или скопируйте файл на каждую ноду."
    fi

    # Disk storage: существует и поддерживает образы дисков
    if ! storage_has_content "$disk_storage" images; then
        log_error "Хранилище дисков '${disk_storage}' не найдено или не поддерживает тип контента 'Disk image'."
        exit 1
    fi
    log_ok "Хранилище дисков '${disk_storage}' доступно."
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
    local image_path="${image_dir}/${image_name}"

    # Определяем формат ОС-диска (учитывает тип хранилища).
    # resolve_disk_format() возвращает в stdout ТОЛЬКО формат,
    # а логи пишет в stderr — это критично для корректного захвата.
    local format
    format="$(resolve_disk_format "$disk_format" "$disk_storage")"

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
    vm_created=1   # с этого момента при ошибке сработает откат

    # 2. EFI-диск создаётся ТОЛЬКО для UEFI (ovmf)
    if [[ "$bios_type" == "ovmf" ]]; then
        log_info "Настройка UEFI: создание EFI-диска..."
        local efi_opts="efitype=4m,ms-cert=2023k,pre-enrolled-keys=1"
        local stype
        stype="$(get_storage_type "$disk_storage")"
        case "$stype" in
            dir|nfs|cifs|cephfs|btrfs|glusterfs)
                # На файловых хранилищах raw не умеет снапшоты → форсируем qcow2,
                # иначе ВСЯ ВМ потеряет возможность снапшотов из-за efidisk
                log_info "Файловое хранилище (${stype}): EFI-диск в формате qcow2" >&2
                efi_opts+=",format=qcow2"
                ;;
        esac
        qm set "$template_id" --efidisk0 "${disk_storage}:1,${efi_opts}"
    else
        log_warn "Выбран Legacy BIOS (seabios): EFI-диск не создаётся."
    fi

    # 3. CD-ROM (опционально, для отладки)
    qm set "$template_id" --ide2 none,media=cdrom

    # 4. Импорт образа с учётом формата
    log_info "Импорт диска..."
    if [[ -n "$format" ]]; then
        qm importdisk "$template_id" "$image_path" "$disk_storage" --format "$format"
    else
        qm importdisk "$template_id" "$image_path" "$disk_storage"
    fi

    # 5. Подключение импортированного диска как scsi0.
    #    Имя тома читаем из ключа unused0 конфига — это работает для ЛЮБОГО
    #    хранилища (lvm-thin, dir, NFS, CIFS, ZFS) и при ЛЮБОМ BIOS.
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
    qm set "$template_id" --scsi1 "${disk_storage}:cloudinit"

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
    qm set "$template_id" --cicustom "vendor=${snippet_storage}:snippets/${SNIPPET_YAML}"

    # 10. Превращение в шаблон
    log_info "Конвертация в шаблон..."
    qm template "$template_id"
    vm_created=0   # шаблон готов, откат больше не нужен

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
  Disk storage: ${disk_storage}
  CI user:      ${ci_username}
  Snippets:     ${snippet_storage}
  Образ:        ${image_dir}/${image_name}
  SSH-ключи:    ${SSH_KEYS_PATH}
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
    bios_type="$(ask "BIOS (ovmf / seabios)" "$bios_type")"
    disk_storage="$(ask "Storage для диска" "$disk_storage")"
    ci_username="$(ask "Имя пользователя (Cloud-Init)" "$ci_username")"
    snippet_storage="$(ask "Storage для snippets" "$snippet_storage")"
    image_dir="$(ask "Директория с образом" "$image_dir")"
    image_name="$(ask "Имя файла образа" "$image_name")"

    log_ok "Параметры настроены."
    show_summary
}

main_menu() {
    cat <<MENU

========================================
  Proxmox Ubuntu 24.04 Cloud-Init Template
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
