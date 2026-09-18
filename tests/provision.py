import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(sys.argv.pop(1)).read_text()
LIBRARY, ENTRYPOINT = SOURCE.rsplit('\nmain "$@"', 1)
assert not ENTRYPOINT.strip()

MOCKS = r'''
[() {
  if [[ "$1" == -b ]]; then
    return "${BLOCK_STATUS:-0}"
  fi
  builtin [ "$@"
}
id() { echo 0; }
readlink() {
  if [[ "$2" == /dev/disk/by-id/test ]]; then
    echo /dev/target
  else
    printf '%s\n' "$2"
  fi
}
findmnt() { echo /dev/root; }
lsblk() {
  case "$*" in
    *"--output TYPE"*) echo "${KIND:-disk}" ;;
    *"--output NAME"*)
      [[ "${ROOT_QUERY_FAIL:-0}" == 0 ]] || return 1
      printf '%s' "${ROOT_DEVICES-/dev/root}"
      ;;
    *"--output MOUNTPOINTS"*)
      [[ "${MOUNT_QUERY_FAIL:-0}" == 0 ]] || return 1
      printf '%s' "${MOUNTS-}"
      ;;
    *) echo /dev/target ;;
  esac
}
stat() { echo "${BLOB_SIZE:-64}"; }
installer() {
  echo install >> "$EVENTS"
  return "${INSTALL_STATUS:-0}"
}
dd() {
  echo dd >> "$EVENTS"
  return "${DD_STATUS:-0}"
}
sync() { :; }
sha256sum() {
  if [[ "$#" == 0 ]]; then
    cat >/dev/null
  fi
  echo 'matching-hash  -'
}
disko_install=installer
blob="$TEST_BLOB"
extra_files=(${TEST_EXTRA_FILES:-})
uboot_offset=32768
root_start_bytes=16777216
'''


class ProvisionTests(unittest.TestCase):
    def run_script(self, command, *, env=None, answer="/dev/target\n", mocks=True, extra=b"psk_rock=secret\n"):
        with tempfile.TemporaryDirectory() as directory:
            blob = Path(directory) / "u-boot-rockchip.bin"
            blob.write_bytes(b"firmware" * 8)
            extra_file = Path(directory) / "extra.conf"
            if extra is not None:
                extra_file.write_bytes(extra)
            events = Path(directory) / "events"
            variables = dict(
                os.environ,
                TEST_BLOB=str(blob),
                TEST_EXTRA_FILES=str(extra_file),
                EVENTS=str(events),
            )
            variables.update(env or {})
            result = subprocess.run(
                ["bash", "-c", LIBRARY + "\n" + (MOCKS if mocks else "") + "\n" + command],
                input=answer,
                text=True,
                capture_output=True,
                env=variables,
            )
            history = events.read_text().splitlines() if events.exists() else []
            return result, history

    def reject(self, command, message, **kwargs):
        result, events = self.run_script(command, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)
        self.assertEqual(events, [])

    def test_partition_and_mapper_targets(self):
        for kind in ("part", "crypt", "lvm", "rom"):
            with self.subTest(kind=kind):
                self.reject('main provision /dev/target', 'not a whole disk', env={"KIND": kind})

    def test_non_block_target(self):
        self.reject('main provision /dev/target', 'not a block device', env={"BLOCK_STATUS": "1"})

    def test_root_and_all_ancestors(self):
        for devices in ("/dev/target", "/dev/root\n/dev/mapper/pool\n/dev/target\n"):
            with self.subTest(devices=devices):
                self.reject('main provision /dev/target', 'running root', env={"ROOT_DEVICES": devices})

    def test_root_query_failure(self):
        self.reject('main provision /dev/target', 'cannot identify disks', env={"ROOT_QUERY_FAIL": "1"})

    def test_empty_root_query(self):
        self.reject('main provision /dev/target', 'no devices found', env={"ROOT_DEVICES": ""})

    def test_mount_query_failure(self):
        self.reject('main provision /dev/target', 'cannot check mounted', env={"MOUNT_QUERY_FAIL": "1"})

    def test_mounts_and_swap_block_both_writes(self):
        for action in ("provision", "write-uboot"):
            for mounts in ("/mnt", "\n/mnt/backup\n", "[SWAP]"):
                with self.subTest(action=action, mounts=mounts):
                    self.reject(f'main {action} /dev/target', 'mounted filesystems or active swap', env={"MOUNTS": mounts})

    def test_empty_and_oversized_firmware(self):
        for size, message in (("0", "empty"), ("16777216", "overlaps")):
            with self.subTest(size=size):
                self.reject('main provision /dev/target', message, env={"BLOB_SIZE": size})

    def test_missing_firmware(self):
        self.reject('blob=/missing; main provision /dev/target', 'missing')

    def test_declined_confirmation(self):
        self.reject('main provision /dev/target', 'aborted', answer="no\n")

    def test_missing_confirmation(self):
        result, events = self.run_script('main provision /dev/target', answer="")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, [])

    def test_invalid_arguments(self):
        for arguments in ("", "provision", "invalid /dev/target", "provision /dev/target extra"):
            with self.subTest(arguments=arguments):
                self.reject(f'main {arguments}', 'usage:')

    def test_install_failure_prevents_bootloader_write(self):
        result, events = self.run_script('main provision /dev/target', env={"INSTALL_STATUS": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, ["install"])

    def test_extra_file_copied_to_installation(self):
        result, events = self.run_script(
            'installer() { printf "install %s\\n" "$*" >> "$EVENTS"; }\nmain provision /dev/target'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--extra-files", events[0])
        self.assertEqual(events[0].count("extra.conf"), 2, events[0])

    def test_missing_or_empty_extra_file_skips_copy(self):
        for extra in (None, b""):
            with self.subTest(extra=extra):
                result, events = self.run_script(
                    'installer() { printf "install %s\\n" "$*" >> "$EVENTS"; }\nmain provision /dev/target',
                    extra=extra,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("--extra-files", events[0])
                self.assertIn("will not be installed", result.stderr)

    def test_write_failure_prevents_verification(self):
        result, events = self.run_script('main provision /dev/target', env={"DD_STATUS": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, ["install", "dd"])
        self.assertNotIn("Done.", result.stdout)

    def test_read_failure_cannot_pass_verification(self):
        result, events = self.run_script('main verify-uboot /dev/target', env={"DD_STATUS": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(events, ["dd"])
        self.assertNotIn("matches", result.stdout)

    def test_symlink_provisioning(self):
        result, events = self.run_script('main provision /dev/disk/by-id/test')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events, ["install", "dd", "dd"])
        self.assertIn("boot from /dev/target", result.stdout)

    def test_verify_regular_file_bytes(self):
        result, _ = self.run_script(r'''
blob="$TEST_BLOB"
uboot_offset=32768
device="$TEST_BLOB.disk"
dd if=/dev/zero of="$device" bs=65536 count=1 status=none
write_uboot "$device"
verify_uboot "$device"
printf x | dd of="$device" bs=1 seek=32768 conv=notrunc status=none
verify_uboot "$device"
''', mocks=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("matches", result.stdout)
        self.assertIn("does not match", result.stderr)


if __name__ == "__main__":
    unittest.main()
