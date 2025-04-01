{ config, lib, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    
    extraConfig = ''
      set clipboard=unnamedplus
      set number
      set relativenumber
      set tabstop=4
      set shiftwidth=4
      set expandtab
    '';
    
    plugins = with pkgs.vimPlugins; [
      {
        plugin = nvim-treesitter;
        config = ''
          lua << EOF
          require('nvim-treesitter.configs').setup {
            ensure_installed = "all",
            highlight = {
              enable = true,
            },
          }
          EOF
        '';
      }
      {
        plugin = nvim-lspconfig;
        config = ''
          lua << EOF
          local lspconfig = require('lspconfig')
          lspconfig.pyright.setup {}
          lspconfig.tsserver.setup {}
          EOF
        '';
      }
    ];
  };
}