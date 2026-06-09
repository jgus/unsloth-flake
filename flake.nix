{
  description = "unsloth: 2x-faster LLM finetuning, version-bumped ahead of nixpkgs via an overlay over the nixpkgs python3Packages.unsloth derivation.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-lib = {
      url = "github:jgus/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flake-lib }:
    let
      pin = import ./pin.nix;
      inherit (pin) version hash;
      source = { type = "pypi"; pname = "unsloth"; format = "sdist"; };

      # Bump via pythonPackagesExtensions, not packageOverrides: consumers (unsloth-studio) resolve deps through the interpreter self-reference `python.pkgs`, which only reflects extensions, not packageOverrides. Reuse nixpkgs' curated derivation (deps, postPatch, pythonRelaxDeps/RemoveDeps) and change only version + src; cuda config flows through nixpkgs' torch/xformers/bitsandbytes unchanged.
      overlay = final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (pyfinal: pyprev: {
            unsloth = pyprev.unsloth.overridePythonAttrs (prevAttrs: {
              inherit version;
              src = pyfinal.fetchPypi {
                pname = "unsloth";
                inherit version hash;
              };
              # unsloth ${version} requires unsloth_zoo>=${version}. Standalone build-verify here resolves zoo from nixpkgs (older); relaxing keeps that build green. The real consumer overlays the matching unsloth-zoo bump, so the constraint is satisfied there.
              pythonRelaxDeps = (prevAttrs.pythonRelaxDeps or [ ]) ++ [ "unsloth_zoo" ];
            });
          })
        ];
      };
    in
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ overlay ];
          };
        in
        {
          packages = {
            unsloth = pkgs.python3.pkgs.unsloth;
            default = pkgs.python3.pkgs.unsloth;
            update-version = flake-lib.lib.mkUpdateVersion {
              inherit pkgs source;
              buildAttr = "unsloth";
            };
            update-branches = flake-lib.lib.mkUpdateBranches {
              inherit pkgs source;
              pinSchema = "pypi";
            };
          };
        }) // {
      overlays.default = overlay;
    };
}
