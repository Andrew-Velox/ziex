# This flake does not package ziex.
# It allows nix users to `nix run github:ziex-dev/ziex` which builds
# and runs the `zx` binary. The build is not done inside a sandbox.
#
# This allows you to bootstrap a ziex project and then use whatever
# zig dev environment you are comfortable with.
{
  description = "Framework for building web applications with zig";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = {nixpkgs, ...}:
    with builtins;
    with nixpkgs.lib;
  let
    forAllSystems = f: genAttrs systems.flakeExposed (s: f nixpkgs.legacyPackages.${s});
  in {
    apps = forAllSystems (pkgs: {
      default = {
        type = "app";
        meta.description = "Ziex: framework for building web applications with Zig";
        program = toString (pkgs.writeShellApplication {
          name = "zx";
          runtimeInputs = [pkgs.zig_0_16];
          text = ''
            tmp="$(mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT
            export ZIG_LOCAL_CACHE_DIR="$tmp/cache"
            export ZIG_GLOBAL_CACHE_DIR="$tmp/cache"
            mkdir -p "$ZIG_LOCAL_CACHE_DIR"
            zig build -p "$tmp/out" -Doptimize=Debug -Dexclude-lsp=true
            "$tmp/out/bin/zx" "$@"
            '';
        }) + "/bin/zx";
      };
    });
  };
}