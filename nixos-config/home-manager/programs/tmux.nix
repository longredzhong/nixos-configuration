{
  "home-manager": {
    "programs": {
      "tmux": {
        "enable": true,
        "config": {
          "default-shell": "/run/current-system/sw/bin/bash",
          "set-option": {
            "prefix": "C-a",
            "mouse": "on"
          },
          "bind": {
            "key": "c": "new-window",
            "key": "n": "next-window",
            "key": "p": "previous-window"
          }
        }
      }
    }
  }
}