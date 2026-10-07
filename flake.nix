{
  description = "Tonk Desktop";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          # Use the selected Xcode toolchain for Swift and Apple's frameworks.
          swift = pkgs.writeShellScriptBin "swift" ''
            unset SDKROOT
            exec /usr/bin/xcrun --sdk macosx swift "$@"
          '';
          xcrun = pkgs.writeShellScriptBin "xcrun" ''
            unset SDKROOT
            exec /usr/bin/xcrun "$@"
          '';
          commands =
            map
              (
                command:
                pkgs.writeTextFile {
                  name = builtins.replaceStrings [ ":" ] [ "-" ] command;
                  destination = "/bin/${command}";
                  executable = true;
                  text = ''
                    #!${pkgs.bash}/bin/bash
                    set -euo pipefail
                    root=$(/usr/bin/git rev-parse --show-toplevel) || exit 1
                    if [[ ! -f "$root/scripts/dev.sh" || ! -f "$root/Package.swift" ]]; then
                      echo "Run ${command} from the Tonk Desktop repository." >&2
                      exit 1
                    fi
                    exec ${pkgs.bash}/bin/bash "$root/scripts/dev.sh" ${command} "$@"
                  '';
                }
              )
              [
                "dev:build"
                "dev:install"
                "dev:open"
                "dev:run"
                "dev:help"
                "test:unit"
                "test:smoke"
              ];
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              swift
              xcrun
              pkgs.nodejs_22
              pkgs.python3
              pkgs.nixfmt
            ]
            ++ commands;
            shellHook = ''
              if [[ $- == *i* || ''${DIRENV_IN_ENVRC:-} == 1 ]]; then
                dev:help >&2
              fi
            '';
          };
        }
      );
    };
}
