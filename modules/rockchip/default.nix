{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.rockchip;
in
{
  imports = [ ./rk3399 ];

  options.hardware.rockchip = {
    enable = lib.mkEnableOption "Rockchip SoC support";

    platformFirmware = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "U-Boot package written at the firmware offset. The board module sets it.";
    };

    firmwareOffset = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 32768;
      description = "Offset in bytes where the installer writes the U-Boot package.";
    };

    rootStart = lib.mkOption {
      type = lib.types.str;
      default = "16M";
      description = "Start of the first partition. The default leaves room for U-Boot in front of it.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = lib.mkBefore [
      "console=tty0"
      "console=ttyS2,1500000n8"
    ];
  };
}
