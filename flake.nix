{
  description = "NixOS board support for the Radxa ROCK 4B+";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    rockchip.url = "github:nabam/nixos-rockchip/v26.05.20260627.714a5f8";

    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      rockchip,
      disko,
    }:
    let
      lib = nixpkgs.lib;

      boardSystem = "aarch64-linux";

      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      board = {
        inherit boardSystem;
        firmwareOffset = 32768;
        rootStart = "16M";
        uboot = rockchip.packages.${boardSystem}.uBootRadxaRock4;
        kernelPackages = rockchip.legacyPackages.${boardSystem}.kernel_linux_latest_rockchip_stable;
      };

      substituters = {
        extra-substituters = [ "https://nabam-nixos-rockchip.cachix.org" ];
        extra-trusted-public-keys = [
          "nabam-nixos-rockchip.cachix.org-1:BQDltcnV8GS/G86tdvjLwLFz1WeFqSk7O9yl+DR0AVM="
        ];
      };

      toBytes =
        value:
        let
          parts = builtins.match "([0-9]+)([KMG]?)" value;
          scale = {
            "" = 1;
            K = 1024;
            M = 1024 * 1024;
            G = 1024 * 1024 * 1024;
          };
        in
        if parts == null then
          throw "expected a size such as 16M, got ${value}"
        else
          (lib.toInt (builtins.elemAt parts 0)) * scale.${builtins.elemAt parts 1};

      provision =
        {
          pkgs,
          flake,
          config,
          extraFiles ? [ ],
          uboot ? board.uboot,
          firmwareOffset ? board.firmwareOffset,
          rootStart ? board.rootStart,
        }:
        pkgs.writeShellApplication {
          name = "provision-${config}";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.util-linux
            pkgs.gnugrep
          ];
          text =
            lib.replaceStrings
              [
                "@UBOOT@"
                "@UBOOT_OFFSET@"
                "@ROOT_START_BYTES@"
                "@FLAKE@"
                "@CONFIG@"
                "@DISKO_INSTALL@"
                "@EXTRA_FILES@"
              ]
              [
                (toString uboot)
                (toString firmwareOffset)
                (toString (toBytes rootStart))
                flake
                config
                "${disko.packages.${boardSystem}.disko-install}/bin/disko-install"
                (lib.escapeShellArgs extraFiles)
              ]
              (builtins.readFile ./scripts/provision.sh);
        };

      flakeInputPaths =
        let
          collect =
            flake:
            [ flake.outPath ] ++ lib.concatMap (child: collect child) (lib.attrValues (flake.inputs or { }));
        in
        flake: lib.unique (collect flake);

      formatCheck =
        system:
        (pkgsFor system).runCommand "check-format"
          {
            nativeBuildInputs = [ (pkgsFor system).nixfmt ];
          }
          ''
            find ${self} -name '*.nix' -print0 | xargs -0 -r nixfmt --check
            touch $out
          '';

      scriptCheck =
        system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.runCommand "check-scripts"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.shellcheck
            ];
          }
          ''
            shellcheck --shell=bash ${./scripts/provision.sh}
            python3 ${./tests/provision.py} ${./scripts/provision.sh}
            touch $out
          '';
    in
    {
      nixosModules.default = self.nixosModules.radxa-rock-pi-4b-plus;

      nixosModules.radxa-rock-pi-4b-plus = {
        imports = [
          ./modules/rockchip
          ./modules/radxa/rock-pi-4b-plus
        ];
        _module.args.board = board;
      };

      nixosModules.radxa-rock-pi-4b-plus-disk = {
        imports = [
          disko.nixosModules.disko
          ./modules/radxa/rock-pi-4b-plus/disk.nix
        ];
      };

      nixosModules.sd-image =
        { config, ... }:
        {
          imports = [ rockchip.nixosModules.sdImageRockchip ];
          rockchip.uBoot = lib.mkDefault config.hardware.rockchip.platformFirmware;
        };

      packages = forAllSystems (
        system:
        lib.optionalAttrs (system == boardSystem) {
          u-boot = board.uboot;
        }
      );

      lib = {
        inherit (board) uboot firmwareOffset rootStart;
        inherit provision flakeInputPaths substituters;
      };

      nixosConfigurations.example = lib.nixosSystem {
        system = boardSystem;
        modules = [
          self.nixosModules.radxa-rock-pi-4b-plus
          self.nixosModules.radxa-rock-pi-4b-plus-disk
          ./examples/minimal.nix
        ];
      };

      checks = forAllSystems (
        system:
        {
          format = formatCheck system;
          scripts = scriptCheck system;
        }
        // lib.optionalAttrs (system == boardSystem) {
          build = self.nixosConfigurations.example.config.system.build.toplevel;
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          packages = with pkgsFor system; [
            just
            coreutils
            nixfmt
            python3
            shellcheck
          ];
        };
      });
    };
}
