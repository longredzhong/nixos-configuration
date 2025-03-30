{ 
  "programs.neovim": {
    "enable": true,
    "editor": {
      "plugins": [
        {
          "name": "nvim-treesitter",
          "enabled": true,
          "config": {
            "ensure_installed": "all",
            "highlight": {
              "enable": true
            }
          }
        },
        {
          "name": "nvim-lspconfig",
          "enabled": true,
          "config": {
            "servers": {
              "pyright": {},
              "tsserver": {}
            }
          }
        }
      ],
      "settings": {
        "clipboard": "unnamedplus",
        "number": true,
        "relativenumber": true,
        "tabstop": 4,
        "shiftwidth": 4,
        "expandtab": true
      }
    }
  }
}