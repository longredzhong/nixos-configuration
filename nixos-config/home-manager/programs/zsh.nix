{ 
  "programs": {
    "zsh": {
      "enable": true,
      "ohMyZsh": {
        "enable": true,
        "themes": {
          "theme": "agnoster"
        },
        "plugins": [
          "git",
          "docker",
          "zsh-autosuggestions",
          "zsh-syntax-highlighting"
        ]
      },
      "extraConfig": ''
        # Custom Zsh configurations can be added here
        export PATH=$HOME/.local/bin:$PATH
      ''
    }
  }
}