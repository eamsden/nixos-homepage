rec {
  description = "The nixos.org homepage";

  # This is used to build the site.
  inputs.nixpkgs = { url = "nixpkgs/nixos-unstable"; };

  # These inputs are used for the manuals and release artifacts
  inputs.released-nixpkgs-unstable = { url = "nixpkgs/nixos-unstable"; };
  inputs.released-nixpkgs-stable = { url = "nixpkgs/nixos-20.09"; };
  inputs.released-nix-unstable = { url = "github:nixos/nix/master"; };
  inputs.released-nix-stable = { url = "github:nixos/nix/latest-release"; flake = false; };
  inputs.nix-pills = { url = "github:NixOS/nix-pills"; flake = false; };
  inputs.nix-dev = { url = "github:nix-dot-dev/nix.dev"; };
  inputs.nixos-common-styles = { url = "github:NixOS/nixos-common-styles"; };

  outputs =
    { self
    , nixpkgs
    , released-nixpkgs-unstable
    , released-nixpkgs-stable
    , released-nix-unstable
    , released-nix-stable
    , nix-pills
    , nix-dev
    , nixos-common-styles
    }:
    let
      system = "x86_64-linux";

      overlay = final: prev: {
        asciinema-scenario = final.rustPlatform.buildRustPackage rec {
          pname = "asciinema-scenario";
          version = "0.2.0";
          src = final.fetchCrate {
            inherit pname version;
            sha256 = "sha256-qMGi+myppWBapM7TkPeXC2g/M1FA1YGwESNrx8LVXkw=";
          };
          cargoSha256 = "1jb34b634wkn5zhzipwi67761qsbr2qvjkd6kz3031hapl457r0b";
        };
      };

      pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
      inherit (pkgs.lib) getVersion;

      pkgs-unstable = import released-nixpkgs-unstable { inherit system; };
      pkgs-stable = import released-nixpkgs-stable { inherit system; };

      nix_stable = (import "${released-nix-stable}/release.nix" {
        nix = released-nix-stable;
        nixpkgs = released-nixpkgs-stable;
        officialRelease = true;
      }).build."${system}";
      nix_unstable = released-nix-unstable.packages."${system}".nix;

      nixPills = import nix-pills {
        inherit pkgs;
        revCount = nix-pills.lastModifiedDate; # FIXME
        shortRev = nix-pills.shortRev;
      };

      nixosAmis = pkgs.writeText "ec2-amis.json"
        (builtins.toJSON (
          import (released-nixpkgs-stable + "/nixos/modules/virtualisation/ec2-amis.nix")));

      serve =
        let
          pythonEnv = pkgs.python3.buildEnv.override {
            extraLibs = with pkgs.python3Packages; [ click livereload ];
          };
        in
          pkgs.writeShellScriptBin "serve" ''exec "${pythonEnv}/bin/python" "${toString ./.}/scripts/run.py" "$@"'';

    in rec {
      defaultPackage."${system}" = packages."${system}".homepage;

      checks."${system}".build = defaultPackage."${system}";

      packages."${system}" = rec {
        siteStyles = pkgs.callPackage ./site-styles { inherit nixos-common-styles system; };

        homepage = pkgs.stdenv.mkDerivation {
          name = "nixos-homepage-${self.lastModifiedDate}";

          src = self;

          enableParallelBuilding = true;

          buildInputs = with pkgs; [
              asciinema-scenario
              gnused
              imagemagick
              jq
              libxml2
              libxslt
              linkchecker
              nixFlakes
              perl
              perlPackages.AppConfig
              perlPackages.JSON
              perlPackages.TemplatePluginIOAll
              perlPackages.TemplatePluginJSONEscape
              perlPackages.TemplateToolkit
              perlPackages.XMLSimple
              serve
              xhtml1
              xidel
            ];

          preBuild = ''
            export NIX_DB_DIR=$TMPDIR
            export NIX_STATE_DIR=$TMPDIR
          '';

          makeFlags =
            [ "NIX_STABLE_VERSION=${getVersion nix_stable.name}"
              "NIX_MANUAL_STABLE_IN=${nix_stable}/share/doc/nix/manual"
              "NIXPKGS_MANUAL_STABLE_IN=${released-nixpkgs-stable.htmlDocs.nixpkgsManual}"
              "NIXOS_MANUAL_STABLE_IN=${released-nixpkgs-stable.htmlDocs.nixosManual}"
              "NIXOS_STABLE_SERIES=${pkgs-stable.lib.trivial.release}"

              "NIX_UNSTABLE_VERSION=${getVersion nix_unstable.name}"
              "NIX_MANUAL_UNSTABLE_IN=${nix_unstable.doc}/share/doc/nix/manual"
              "NIXPKGS_MANUAL_UNSTABLE_IN=${released-nixpkgs-unstable.htmlDocs.nixpkgsManual}"
              "NIXOS_MANUAL_UNSTABLE_IN=${released-nixpkgs-unstable.htmlDocs.nixosManual}"
              "NIXOS_UNSTABLE_SERIES=${pkgs-unstable.lib.trivial.release}"

              "NIXOS_AMIS=${nixosAmis}"
              "NIXOS_COMMON_STYLES=${nixos-common-styles.packages."${system}".commonStyles}"
              "NIXOS_SITE_STYLES=${siteStyles}"
              "NIX_PILLS_MANUAL_IN=${nixPills}/share/doc/nix-pills"
              "NIX_DEV_MANUAL_IN=${nix-dev.defaultPackage.x86_64-linux}/html"

              "-j 1"
            ];

          doCheck = true;

          installPhase = ''
            mkdir $out
            cp -prd . $out/
          '';

          shellHook = ''
            export NIX_STABLE_VERSION="${getVersion nix_stable.name}"
            export NIX_MANUAL_STABLE_IN="${nix_stable}/share/doc/nix/manual"
            export NIXPKGS_MANUAL_STABLE_IN="${released-nixpkgs-stable.htmlDocs.nixpkgsManual}"
            export NIXOS_MANUAL_STABLE_IN="${released-nixpkgs-stable.htmlDocs.nixosManual}"
            export NIXOS_STABLE_SERIES="${pkgs-stable.lib.trivial.release}"

            export NIX_UNSTABLE_VERSION="${getVersion nix_unstable.name}"
            export NIX_MANUAL_UNSTABLE_IN="${nix_unstable.doc}/share/doc/nix/manual"
            export NIXPKGS_MANUAL_UNSTABLE_IN="${released-nixpkgs-unstable.htmlDocs.nixpkgsManual}"
            export NIXOS_MANUAL_UNSTABLE_IN="${released-nixpkgs-unstable.htmlDocs.nixosManual}"
            export NIXOS_UNSTABLE_SERIES="${pkgs-unstable.lib.trivial.release}"

            export NIXOS_AMIS="${nixosAmis}"
            export NIXOS_COMMON_STYLES="${nixos-common-styles.packages."${system}".commonStyles}"
            export NIXOS_SITE_STYLES=""
            export NIX_PILLS_MANUAL_IN="${nixPills}/share/doc/nix-pills"
            export NIX_DEV_MANUAL_IN="${nix-dev.defaultPackage.x86_64-linux}/html"

            echo ""
            echo "  To start developing run:"
            echo "      serve"
            echo ""
            echo "  and go to the following URL in your browser:"
            echo "      https://127.0.0.1:8000/"
            echo ""
            echo "  It will rebuild the website on each change."
            echo ""
          '';
        };
      };

      nixosConfigurations.container = nixpkgs.lib.nixosSystem {
        inherit system;
        modules =
          [ ({ lib, ... }:
            { system.configurationRevision = lib.mkIf (self ? rev) self.rev;
              boot.isContainer = true;
              networking.useDHCP = false;
              networking.firewall.allowedTCPPorts = [ 80 ];
              services.httpd = {
                enable = true;
                adminAddr = "admin@example.org";
                virtualHosts.default = {
                  documentRoot = packages."${system}".homepage;
                };
              };
            })
          ];
      };

  };
}
