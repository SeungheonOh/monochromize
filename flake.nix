{
  description = "drmfilter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-nix.url = "github:input-output-hk/haskell.nix";
  };

  outputs = inputs@{ flake-parts, nixpkgs, haskell-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      debug = true;
      systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" "aarch64-linux" ];

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
            compiler-nix-name = "ghc966"; # << idk what version of ghc kubernetes-client supports
            index-state = "2024-10-09T22:38:57Z";
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
          packages = flake.packages // {
          };

          inherit (flake) checks;
        };
    };
}
