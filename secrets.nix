let
  # 用户密钥（需要替换为实际的公钥）
  longred =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFjn1fjQIAWN6VGEWa6z9uIbJg9i4HN9F+cUJlJVnYB6";

  # 系统密钥（需要替换为实际的系统公钥）
  metacube-wsl =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgE5FxFo9L7fPcDsH4wHvvlEFROECkRmYfBRfQrj9LD root@metacube-wsl";
  thinkbook-wsl =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMmGXHZcFrrZl0o0KOzbbjekYvE7T450I+VbGJUUrCwu root@thinkbook-wsl";
  nuc =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ7rzTx+Fz7FLZ58b6qR4kJ8Q9QP37oHRrTHKVWkUVZV root@nuc";

  # 定义密钥组
  allSystems = [ metacube-wsl thinkbook-wsl nuc ];
  allUsers = [ longred ];
  everyone = allSystems ++ allUsers;
in {
  # SSH 密钥
  "secrets/ssh/id_ed25519.age".publicKeys = [ longred ];
  "secrets/ssh/id_ed25519.pub.age".publicKeys = everyone;
  "secrets/ssh/config.age".publicKeys = everyone;
  "secrets/ssh/known_hosts.age".publicKeys = everyone;

  # 示例 API 密钥
  "secrets/api_keys/github_token.age".publicKeys = [ longred ];
  "secrets/api_keys/openai_api_key.age".publicKeys = everyone;

  # 示例服务密码
  "secrets/passwords/db_password.age".publicKeys = allSystems;
}
