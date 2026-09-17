{
  config,
  lib,
  board,
  ...
}:

let
  cfg = config.hardware.rockchip.rk3399;
in
{
  options.hardware.rockchip.rk3399 = {
    enable = lib.mkEnableOption "Rockchip RK3399 support";

    kernelPackages = lib.mkOption {
      type = lib.types.raw;
      default = board.kernelPackages;
      description = "Kernel and modules. The default is the Rockchip build these boards were tested with, not the consumer's nixpkgs kernel.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.rockchip.enable = true;

    boot.kernelPackages = cfg.kernelPackages;
    boot.kernelModules = [ "phy-rockchip-inno-hdmi" ];
  };
}
