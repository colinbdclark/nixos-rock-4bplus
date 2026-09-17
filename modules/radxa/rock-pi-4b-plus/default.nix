{
  lib,
  board,
  ...
}:

{
  imports = [ ./wireless.nix ];

  hardware.rockchip.rk3399.enable = true;
  hardware.rockchip.platformFirmware = lib.mkDefault board.uboot;

  hardware.deviceTree.filter = "rk3399-rock-pi-4b-plus.dtb";
  hardware.deviceTree.name = "rockchip/rk3399-rock-pi-4b-plus.dtb";

  boot.supportedFilesystems.zfs = lib.mkForce false;
}
