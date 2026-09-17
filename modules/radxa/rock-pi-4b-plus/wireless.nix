{ pkgs, ... }:

let
  firmware =
    pkgs.runCommand "aw-nb197sm-firmware"
      {
        meta.priority = 1;
      }
      ''
        mkdir -p $out/lib/firmware/brcm
        cp ${../../../vendor/aw-nb197sm/nvram_azw372.txt} \
          "$out/lib/firmware/brcm/brcmfmac43430-sdio.radxa,rockpi4b-plus.txt"
        cp ${../../../vendor/aw-nb197sm/BCM4343A1.hcd} "$out/lib/firmware/brcm/BCM43430A1.hcd"
      '';
in
{
  hardware.firmware = [
    firmware
    pkgs.raspberrypifw
  ];
}
