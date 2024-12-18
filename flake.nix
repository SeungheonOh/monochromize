{
  description = "monochromize";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-nix.url = "github:input-output-hk/haskell.nix";
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, haskell-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
      ];

      debug = true;
      systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" "aarch64-linux" ];

      flake = {
        nixosModules.default = { ... }: {
          imports = [
            { nixpkgs.overlays = [ self.overlays.default ]; }
            ./nix/nixos-module.nix
          ];
        };
      };


      perSystem = { config, system, lib, self', ... }:
        let
          pkgs =
            import haskell-nix.inputs.nixpkgs {
              inherit system;
              overlays = [
                haskell-nix.overlay
              ];
              inherit (haskell-nix) config;
            };
          project = pkgs.haskell-nix.cabalProject' {
            src = ./.;
            compiler-nix-name = "ghc966";
            shell = {
              withHoogle = true;
              withHaddock = true;
              exactDeps = false;
            };
          };
          flake = project.flake { };

        in
        {
          inherit (flake) devShells;
          packages = flake.packages // {};
          overlayAttrs = {
            monochromize = config.packages."monochromize:exe:monochromize";
          };

          inherit (flake) checks;
        };
    };
}
