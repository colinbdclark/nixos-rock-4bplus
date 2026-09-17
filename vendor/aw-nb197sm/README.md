# AW-NB197SM firmware

These files support the AzureWave AW-NB197SM module on the ROCK 4B+. It uses a
26 MHz crystal and SDIO ID `0x02d0:0xa9a6`.

`modules/radxa/rock-pi-4b-plus/wireless.nix` installs:

- `nvram_azw372.txt` as the board-specific
  `brcm/brcmfmac43430-sdio.radxa,rockpi4b-plus.txt`.
- `BCM4343A1.hcd` as `brcm/BCM43430A1.hcd`, the name requested by the driver.

Only the board-specific name is installed. brcmfmac falls back to the generic
`brcmfmac43430-sdio.txt` name, which the same module supplies through the
Raspberry Pi firmware package. That generic file sets `xtalfreq=37400` for the
Raspberry Pi's crystal, so the board-specific file has to take precedence. This
board uses 26 MHz.

The NVRAM also contains calibration values and placeholder MAC addresses.
Verify the effective addresses and regulatory domain after installation.

## Source

Both files come from Firefly's `rkwifibt` repository at commit
`049f321eea3a53a483795f7293a58068d5787f6c`:

- [NVRAM](https://gitlab.com/firefly-linux/external/rkwifibt/-/raw/049f321eea3a53a483795f7293a58068d5787f6c/firmware/broadcom/AW-NB197/wifi/nvram_azw372.txt)
- [Bluetooth firmware](https://gitlab.com/firefly-linux/external/rkwifibt/-/raw/049f321eea3a53a483795f7293a58068d5787f6c/firmware/broadcom/AW-NB197/bt/BCM4343A1.hcd)

## Licence notice

The source repository includes an Apache 2.0 licence notice, copyright
2005–2008 Android Open Source Project. A copy is in [NOTICE](NOTICE).
