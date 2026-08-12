{ pkgs, ... }:
{
  programs.helix = {
    enable = true;

    settings = {
      theme = "dracula";

      editor = {
        line-number = "relative";
        cursorline = true;
        cursorcolumn = true;
        true-color = true;
        mouse = true;
        bufferline = "multiple";
        color-modes = true;
        idle-timeout = 200;
        completion-trigger-len = 1;
        auto-pairs = true;
        auto-save = true;
        rulers = [ 80 100 ];

        whitespace.render = {
          space = "none";
          tab = "all";
          newline = "none";
        };

        soft-wrap = {
          enable = true;
          wrap-indicator = "↪ ";
        };
      };

      keys.normal = {
        "C-s" = ":write";
        "C-q" = ":quit";
        "C-h" = "jump_view_left";
        "C-j" = "jump_view_down";
        "C-k" = "jump_view_up";
        "C-l" = "jump_view_right";
      };
    };

    languages = {
      language-server = {
        pyright = {
          command = "${pkgs.pyright}/bin/pyright-langserver";
          args = [ "--stdio" ];
        };

        ruff = {
          command = "${pkgs.ruff}/bin/ruff";
          args = [ "server" ];
        };

        typescript-language-server = {
          command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
          args = [ "--stdio" ];
        };

        marksman = {
          command = "${pkgs.marksman}/bin/marksman";
          args = [ "server" ];
        };
      };

      language = [
        {
          name = "python";
          language-servers = [ "pyright" "ruff" ];
          auto-format = true;
          formatter = {
            command = "${pkgs.ruff}/bin/ruff";
            args = [ "format" "--stdin-filename" "file.py" "-" ];
          };
          indent = {
            tab-width = 4;
            unit = "    ";
          };
        }
        {
          name = "javascript";
          language-servers = [ "typescript-language-server" ];
          auto-format = true;
          formatter = {
            command = "${pkgs.prettier}/bin/prettier";
            args = [ "--parser" "babel" ];
          };
          indent = {
            tab-width = 2;
            unit = "  ";
          };
        }
        {
          name = "typescript";
          language-servers = [ "typescript-language-server" ];
          auto-format = true;
          formatter = {
            command = "${pkgs.prettier}/bin/prettier";
            args = [ "--parser" "typescript" ];
          };
          indent = {
            tab-width = 2;
            unit = "  ";
          };
        }
        {
          name = "tsx";
          language-servers = [ "typescript-language-server" ];
          auto-format = true;
          formatter = {
            command = "${pkgs.prettier}/bin/prettier";
            args = [ "--parser" "typescript" ];
          };
          indent = {
            tab-width = 2;
            unit = "  ";
          };
        }
        {
          name = "markdown";
          language-servers = [ "marksman" ];
          auto-format = true;
          formatter = {
            command = "${pkgs.prettier}/bin/prettier";
            args = [ "--parser" "markdown" ];
          };
          indent = {
            tab-width = 2;
            unit = "  ";
          };
        }
      ];
    };
  };

  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };
}
