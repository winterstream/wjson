{
  description = "Minimal Cross-Version Lua Testing Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        makeLuaEnv = lua: lua.withPackages (ps: [ ps.busted ps.luafilesystem ]);
      in
      {
        devShells = {
          luajit = pkgs.mkShell { buildInputs = [ (makeLuaEnv pkgs.luajit) ]; };
          lua52 = pkgs.mkShell { buildInputs = [ (makeLuaEnv pkgs.lua5_2) ]; };
          lua53 = pkgs.mkShell { buildInputs = [ (makeLuaEnv pkgs.lua5_3) ]; };
          lua54 = pkgs.mkShell { buildInputs = [ (makeLuaEnv pkgs.lua5_4) ]; };
          default = pkgs.mkShell { buildInputs = [ (makeLuaEnv pkgs.lua5_4) ]; };
        };
      }
    );
}
