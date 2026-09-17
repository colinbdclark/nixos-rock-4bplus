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

    zfsStub = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Replace the zfs package with commands that fail. Installation paths that reach for zfs need this, because the Rockchip kernel provides no ZFS module.";
    };
  };

  config =
    lib.mkIf cfg.enable {
      boot.kernelParams = lib.mkBefore [
        "console=tty0"
        "console=ttyS2,1500000n8"
      ];
    }
    // lib.mkIf cfg.zfsStub {
      nixpkgs.overlays = [
        (_final: super: {
          zfs = super.runCommandLocal "zfs-unavailable" { } ''
            mkdir -p $out/bin
            for command in zfs zpool zdb; do
              printf '#!${super.runtimeShell}\necho "zfs is not available on this system" >&2\nexit 1\n' > $out/bin/$command
              chmod +x $out/bin/$command
            done
          '';
        })
      ];
    };
}
