# shamelessly stolen from KMonad
{ config, lib, pkgs, ... }:

let
  cfg = config.services.monochromize;
in
{
  options.services.monochromize = {
    enable = lib.mkEnableOption "no color and orange screen";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.monochromize;
      description = "The monochromize package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services."monochromize" = {
      enable = true;

      before = [ "display-manager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.monochromize}/bin/monochromize &";
        Type = "oneshot";
      };

    };
  };
}
