set -euo pipefail

uboot="@UBOOT@"
uboot_offset="@UBOOT_OFFSET@"
root_start_bytes="@ROOT_START_BYTES@"
flake="@FLAKE@"
config="@CONFIG@"
disko_install="@DISKO_INSTALL@"
extra_files=(@EXTRA_FILES@)

usage() {
  echo "usage: $0 {provision|write-uboot|verify-uboot} <device>" >&2
  exit 1
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
}

require_block_device() {
  [ -b "$1" ] || die "$1 is not a block device"
  kind=$(lsblk --nodeps --noheadings --output TYPE "$1") ||
    die "cannot identify device type: $1"
  case "$kind" in
    disk|loop) ;;
    *) die "$1 is not a whole disk" ;;
  esac
}

reject_running_root() {
  root_source=$(findmnt -no SOURCE /) || die "cannot identify the running root"
  root_source=$(readlink -f "$root_source") || die "cannot resolve the running root"
  root_devices=$(lsblk --inverse --noheadings --raw --paths --output NAME "$root_source") ||
    die "cannot identify disks holding the running root"
  [ -n "$root_devices" ] || die "no devices found for the running root"
  for root_device in $root_devices; do
    [ "$root_device" != "$1" ] ||
      die "refusing to touch $1: it holds the running root filesystem"
  done
}

reject_mounted() {
  mounted=$(lsblk --noheadings --raw --output MOUNTPOINTS "$1") ||
    die "cannot check mounted filesystems on $1"
  [ -z "${mounted//[[:space:]]/}" ] ||
    die "refusing to touch $1: it has mounted filesystems or active swap"
}

blob="$uboot/u-boot-rockchip.bin"

check_uboot_fits() {
  [ -f "$blob" ] || die "missing $blob"
  size=$(stat -c %s "$blob")
  [ "$size" -gt 0 ] || die "U-Boot image is empty"
  [ $((uboot_offset + size)) -le "$root_start_bytes" ] ||
    die "U-Boot ($size bytes at $uboot_offset) overlaps the root partition at $root_start_bytes"
  echo "U-Boot: $size bytes at offset $uboot_offset; root partition starts at $root_start_bytes"
}

describe() {
  lsblk -dpo NAME,SIZE,MODEL,TRAN "$1"
}

confirm() {
  printf 'Type the device path (%s) to confirm: ' "$1" >&2
  read -r answer
  [ "$answer" = "$1" ] || die "aborted"
}

write_uboot() {
  device=$1
  echo "Writing U-Boot to byte $uboot_offset of $device"
  dd if="$blob" of="$device" bs=1M oflag=seek_bytes seek="$uboot_offset" conv=fsync
  sync
}

verify_uboot() {
  device=$1
  actual=$(
    dd if="$device" iflag=skip_bytes,count_bytes skip="$uboot_offset" \
      count="$(stat -c %s "$blob")" 2>/dev/null | sha256sum | cut -d' ' -f1
  )
  expected=$(sha256sum "$blob" | cut -d' ' -f1)
  [ "$actual" = "$expected" ] || die "U-Boot on $device does not match $blob"
  echo "U-Boot on $device matches $blob ($expected)"
}

collect_extra_args() {
  extra_args=()
  for file in ${extra_files[@]+"${extra_files[@]}"}; do
    if [ -s "$file" ]; then
      extra_args+=(--extra-files "$file" "$file")
    else
      echo "warning: $file is missing or empty and will not reach the installed system" >&2
    fi
  done
}

provision() {
  device=$1
  require_block_device "$device"
  reject_running_root "$device"
  reject_mounted "$device"
  check_uboot_fits
  describe "$device"
  confirm "$device"

  collect_extra_args
  echo "Installing $config to $device"
  "$disko_install" --flake "$flake#$config" --disk emmc "$device" ${extra_args[@]+"${extra_args[@]}"}

  write_uboot "$device"
  verify_uboot "$device"
  echo "Done. Power off, remove the SD card, and boot from $device."
}

main() {
  action=${1:-}
  device=${2:-}
  [ "$#" -eq 2 ] || usage
  case "$action" in
    provision|write-uboot|verify-uboot) ;;
    *) usage ;;
  esac
  require_root

  resolved=$(readlink -f "$device") || die "cannot resolve device: $device"
  device=$resolved

  case "$action" in
    provision) provision "$device" ;;
    write-uboot)
      require_block_device "$device"
      reject_running_root "$device"
      reject_mounted "$device"
      check_uboot_fits
      describe "$device"
      confirm "$device"
      write_uboot "$device"
      verify_uboot "$device"
      echo "U-Boot rewritten on $device. Reboot before relying on it."
      ;;
    verify-uboot)
      require_block_device "$device"
      check_uboot_fits
      verify_uboot "$device"
      ;;
    *) usage ;;
  esac
}

main "$@"
