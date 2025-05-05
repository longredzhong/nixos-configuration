#!/usr/bin/env python3
"""
密钥管理与机密文件工具 (SecretCtl)
用于管理agenix密钥和加密文件的综合工具
"""

import argparse
import os
import sys
import subprocess
import json
import tempfile
import re
from pathlib import Path


class SecretCtl:
    """主密钥管理类"""
    
    def __init__(self, dry_run=False, yes=False):
        self.config_root = Path(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.secrets_dir = self.config_root / "secrets"
        self.secrets_nix = self.secrets_dir / "secrets.nix"
        self.dry_run = dry_run
        self.yes = yes
        self._cache = {}
        
    def run_nix_eval(self, expr, use_json=True):
        """执行nix eval命令获取数据"""
        # 缓存 nix eval 结果
        if expr in self._cache:
            return self._cache[expr]
        cmd = ["nix", "eval", "--impure"]
        if use_json:
            cmd.append("--json")
        cmd.extend(["--expr", expr])
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            value = json.loads(result.stdout) if use_json else result.stdout.strip()
            self._cache[expr] = value
            return value
        except subprocess.CalledProcessError as e:
            print(f"错误执行nix eval: {e}", file=sys.stderr)
            print(f"错误输出: {e.stderr}", file=sys.stderr)
            sys.exit(1)

    def get_public_keys(self):
        """获取全部公钥"""
        return self.run_nix_eval('(import ./secrets/secrets.nix {}).publicKeys')
    
    def get_key_groups(self):
        """获取密钥组"""
        return self.run_nix_eval('(import ./secrets/secrets.nix {}).keyGroups')
    
    def get_secret_mappings(self):
        """获取密钥映射"""
        return self.run_nix_eval('(import ./secrets/secrets.nix {}).secretMappings')
    
    def get_host_keys(self):
        """获取主机密钥"""
        return self.run_nix_eval('(import ./secrets/secrets.nix {}).publicKeys.hosts')
    
    def get_user_keys(self):
        """获取用户密钥"""
        return self.run_nix_eval('(import ./secrets/secrets.nix {}).publicKeys.users')
    
    def get_recipient_comment(self, secret_name):
        """获取接收者注释"""
        return self.run_nix_eval(
            f'(import ./secrets/secrets.nix {{ lib = builtins // (import <nixpkgs/lib>); }}).getRecipientComment "{secret_name}"', 
            use_json=False
        )

    def list_keys(self, key_type="all"):
        """列出密钥"""
        if key_type in ["all", "hosts"]:
            host_keys = self.get_host_keys()
            print("=== 主机密钥 ===")
            for host, info in host_keys.items():
                key_preview = info["key"][:20] + "..." if len(info["key"]) > 20 else info["key"]
                print(f"{host}: {key_preview}")
                print(f"  类型: {info['type']}")
                print(f"  私钥路径: {info['identityPath']}")
            print()
        
        if key_type in ["all", "users"]:
            user_keys = self.get_user_keys()
            print("=== 用户密钥 ===")
            for user, hosts in user_keys.items():
                print(f"用户: {user}")
                for host, info in hosts.items():
                    key_preview = info["key"][:20] + "..." if len(info["key"]) > 20 else info["key"]
                    print(f"  {host}: {key_preview}")
                    print(f"    类型: {info['type']}")
                    print(f"    私钥路径: {info['identityPath']}")
            print()
            
        if key_type in ["all", "groups"]:
            key_groups = self.get_key_groups()
            print("=== 密钥组 ===")
            for group, _ in key_groups.items():
                print(f"组: {group}")
            
    def list_secrets(self):
        """列出所有机密文件"""
        secret_mappings = self.get_secret_mappings()
        print("=== 机密文件 ===")
        for secret, info in secret_mappings.items():
            print(f"文件: {secret}")
            print(f"  目标路径: {info['targetPath']}")
            print(f"  权限: {info['owner']}:{info['group']} {info['mode']}")
            comment = self.get_recipient_comment(secret)
            print(f"  {comment}")
            print()
    
    def check_consistency(self):
        """检查密钥映射与实际文件的一致性"""
        secret_mappings = self.get_secret_mappings()
        actual_files = [f.name for f in self.secrets_dir.glob("*.age")]
        
        missing_in_mapping = [f for f in actual_files if f not in secret_mappings]
        missing_files = [f for f in secret_mappings if not (self.secrets_dir / f).exists()]
        
        if missing_in_mapping:
            print("错误: 存在但未在secretMappings中定义的.age文件:")
            for f in missing_in_mapping:
                print(f"  - {f}")
        
        if missing_files:
            print("错误: secretMappings中定义但实际不存在的文件:")
            for f in missing_files:
                print(f"  - {f}")
        
        if not missing_in_mapping and not missing_files:
            print("检查通过: 所有.age文件都有对应的映射定义。")
            return True
        return False
    
    def update_secrets_nix(self, content_func):
        """通用方法更新secrets.nix文件"""
        # 首先备份原文件
        backup_path = str(self.secrets_nix) + ".bak"
        with open(self.secrets_nix, 'r') as f:
            original_content = f.read()
        
        with open(backup_path, 'w') as f:
            f.write(original_content)
            
        # 应用内容更新函数
        new_content = content_func(original_content)
        
        # 写回文件，支持 dry-run
        if self.dry_run:
            print(f"[dry-run] would update {self.secrets_nix}")
        else:
            with open(self.secrets_nix, 'w') as f:
                f.write(new_content)
            
        print(f"已更新 {self.secrets_nix}")
        print(f"备份保存在 {backup_path}")
    
    def add_key(self, key_type, name, key, identity_path=None):
        """添加新密钥"""
        if key_type not in ["user", "host"]:
            print(f"错误: 无效的密钥类型 '{key_type}'，支持: user, host", file=sys.stderr)
            return False
            
        # 设置默认身份路径
        if not identity_path:
            if key_type == "user":
                identity_path = f"/home/{name}/.ssh/id_ed25519"
            else:  # host
                identity_path = "/etc/ssh/ssh_host_ed25519_key"
        
        # 构建新密钥条目
        if key_type == "user":
            # 用户密钥需要主机名
            host = os.uname().nodename
            key_entry = f"""
        {host} = {{
          type = "ssh-ed25519";
          key = "{key}";
          identityPath = "{identity_path}";
        }};"""
            
            def update_content(content):
                # 查找用户部分进行更新
                if f"      {name} = {{" in content:
                    # 用户已存在，在其中添加新主机
                    pattern = f"      {name} = {{([^}}]*)}}"
                    replacement = f"      {name} = {{\\1{key_entry}\n      }}"
                    return re.sub(pattern, replacement, content, flags=re.DOTALL)
                else:
                    # 创建新用户
                    new_user = f"""
      {name} = {{{key_entry}
      }};"""
                    # 找到users部分并添加
                    users_pattern = r"(users = {[^}]*)(};)"
                    return re.sub(users_pattern, f"\\1{new_user}\n    \\2", content, flags=re.DOTALL)
        else:  # host
            key_entry = f"""
      {name} = {{
        type = "ssh-ed25519";
        key = "{key}";
        identityPath = "{identity_path}";
      }};"""
            
            def update_content(content):
                # 查找hosts部分进行更新
                hosts_pattern = r"(hosts = {[^}]*)(};)"
                return re.sub(hosts_pattern, f"\\1{key_entry}\n    \\2", content, flags=re.DOTALL)
        
        try:
            print(f"{'[dry-run]' if self.dry_run else ''} add {key_type} key {name}")
            self.update_secrets_nix(update_content)
            if not self.dry_run:
                print(f"已添加{key_type}密钥: {name}")
            print("提示: 您可能需要更新keyGroups以包含新密钥")
            return True
        except Exception as e:
            print(f"添加密钥时出错: {e}", file=sys.stderr)
            return False
            
    def remove_key(self, key_type, name):
        """移除密钥"""
        if key_type not in ["user", "host"]:
            print(f"错误: 无效的密钥类型 '{key_type}'，支持: user, host", file=sys.stderr)
            return False
            
        def update_content(content):
            if key_type == "user":
                # 移除整个用户
                user_pattern = f"      {name} = {{[^}}]*}};\n"
                if not re.search(user_pattern, content, re.DOTALL):
                    print(f"未找到用户 '{name}'")
                    return content
                return re.sub(user_pattern, "", content, flags=re.DOTALL)
            else:  # host
                # 移除主机
                host_pattern = f"      {name} = {{[^}}]*}};\n"
                if not re.search(host_pattern, content, re.DOTALL):
                    print(f"未找到主机 '{name}'")
                    return content
                return re.sub(host_pattern, "", content, flags=re.DOTALL)
        
        try:
            # 确认
            response = input(f"确定要删除{key_type}密钥 '{name}'? 这可能会导致加密文件无法解密。(y/N): ")
            if response.lower() != 'y':
                print("已取消")
                return False
                
            self.update_secrets_nix(update_content)
            print(f"已移除{key_type}密钥: {name}")
            print("警告: 请检查并更新keyGroups和secretMappings以反映此更改")
            return True
        except Exception as e:
            print(f"移除密钥时出错: {e}", file=sys.stderr)
            return False
    
    def add_secret_mapping(self, secret_name, recipients, target_path, owner, group, mode="600"):
        """添加新的密钥映射"""
        if not secret_name.endswith(".age"):
            secret_name += ".age"
            
        # 检查文件是否存在
        if not (self.secrets_dir / secret_name).exists():
            print(f"警告: 密钥文件 '{secret_name}' 不存在")
            response = input("是否继续添加映射? (y/N): ")
            if response.lower() != 'y':
                return False
        
        # 构建映射条目
        mapping_entry = f"""
    "{secret_name}" = {{
      recipients = {recipients};
      targetPath = "{target_path}";
      owner = "{owner}";
      group = "{group}";
      mode = "{mode}";
    }};"""
        
        def update_content(content):
            # 检查是否已存在
            if f'"{secret_name}" = {{' in content:
                print(f"错误: 映射 '{secret_name}' 已存在")
                return content
                
            # 找到secretMappings部分并添加
            mappings_pattern = r"(secretMappings = {[^}]*)(};)"
            return re.sub(mappings_pattern, f"\\1{mapping_entry}\n  \\2", content, flags=re.DOTALL)
        
        try:
            self.update_secrets_nix(update_content)
            print(f"已添加映射: {secret_name}")
            return True
        except Exception as e:
            print(f"添加映射时出错: {e}", file=sys.stderr)
            return False
    
    def expand_recipients(self, recipients):
        """将 keyGroups.xxx 自动展开为实际公钥列表"""
        expanded = []
        for r in recipients:
            if r.startswith("keyGroups."):
                group_name = r[len("keyGroups."):]
                # 获取该组所有公钥
                expr = f'(import ./secrets/secrets.nix {{ lib = builtins // (import <nixpkgs/lib>); }}).groupToKeys (import ./secrets/secrets.nix {{ lib = builtins // (import <nixpkgs/lib>); }}).keyGroups.{group_name}'
                try:
                    keys = self.run_nix_eval(expr)
                    expanded.extend(keys)
                except Exception as e:
                    print(f"展开密钥组 {r} 失败: {e}", file=sys.stderr)
            else:
                expanded.append(r)
        return expanded

    def encrypt_file(self, input_file, recipients, output_file=None):
        """加密文件，支持密钥组"""
        if not os.path.exists(input_file):
            print(f"错误: 文件 '{input_file}' 不存在", file=sys.stderr)
            return False
            
        if not output_file:
            output_file = input_file + ".age"
            
        if os.path.exists(output_file):
            response = input(f"文件 '{output_file}' 已存在，是否覆盖? (y/N): ")
            if response.lower() != 'y':
                print("已取消")
                return False
                
        # 展开密钥组
        real_recipients = self.expand_recipients(recipients)
        
        # 构建age命令
        cmd = ["age", "-o", output_file]
        
        # 添加接收者
        for recipient in real_recipients:
            cmd.extend(["-r", recipient])
            
        cmd.append(input_file)
        
        print(f"{'[dry-run]' if self.dry_run else ''} run: {' '.join(cmd)}")
        if self.dry_run:
            return True
        try:
            subprocess.run(cmd, check=True)
            print(f"文件已加密: {output_file}")
            return True
        except subprocess.CalledProcessError as e:
            print(f"加密失败: {e}", file=sys.stderr)
            return False
    
    def decrypt_edit_reencrypt(self, age_file, identity=None):
        """解密、编辑并重新加密文件"""
        if not os.path.exists(age_file):
            print(f"错误: 文件 '{age_file}' 不存在", file=sys.stderr)
            return False
            
        # 获取秘密映射
        secret_name = os.path.basename(age_file)
        mappings = self.get_secret_mappings()
        
        if secret_name not in mappings:
            print(f"警告: '{secret_name}' 在secrets.nix中没有映射")
            response = input("继续编辑? (y/N): ")
            if response.lower() != 'y':
                return False
        
        # 创建临时文件并设置权限
        tmp = tempfile.NamedTemporaryFile(delete=False)
        tmp_path = tmp.name
        tmp.close()
        os.chmod(tmp_path, 0o600)
        
        try:
            # 解密到临时文件
            decrypt_cmd = ["age", "--decrypt"]
            if identity:
                decrypt_cmd.extend(["-i", identity])
            decrypt_cmd.extend(["-o", tmp_path, age_file])
            
            try:
                subprocess.run(decrypt_cmd, check=True)
            except subprocess.CalledProcessError:
                print("解密失败。尝试其他私钥...", file=sys.stderr)
                # 尝试默认路径
                default_identities = [
                    os.path.expanduser("~/.ssh/id_ed25519"),
                    "/etc/ssh/ssh_host_ed25519_key"
                ]
                decrypted = False
                for ident in default_identities:
                    if os.path.exists(ident):
                        try:
                            decrypt_cmd = ["age", "--decrypt", "-i", ident, "-o", tmp_path, age_file]
                            subprocess.run(decrypt_cmd, check=True)
                            decrypted = True
                            print(f"使用密钥 {ident} 解密成功")
                            break
                        except subprocess.CalledProcessError:
                            continue
                
                if not decrypted:
                    print("无法解密文件。请提供有效的私钥。", file=sys.stderr)
                    os.unlink(tmp_path)
                    return False
            
            # 获取文件修改时间以检测编辑
            initial_mtime = os.path.getmtime(tmp_path)
            
            # 打开编辑器
            editor = os.environ.get("EDITOR", "nano")
            subprocess.run([editor, tmp_path])
            
            # 检查是否被修改
            if os.path.getmtime(tmp_path) == initial_mtime:
                print("文件未被修改，无需重新加密")
                os.unlink(tmp_path)
                return True
            
            # 重新加密
            # 获取接收者列表
            recipients = []
            if secret_name in mappings:
                # 解析接收者注释获取公钥
                comment = self.get_recipient_comment(secret_name)
                print(f"重新加密为原始接收者: {comment}")
                
                # 根据映射获取实际公钥
                expr = f'(import ./secrets/secrets.nix {{}}).groupToKeys (import ./secrets/secrets.nix {{}}).secretMappings."{secret_name}".recipients'
                recipient_keys = self.run_nix_eval(expr)
                recipients = recipient_keys
            
            if not recipients:
                print("警告: 无法确定接收者，请手动指定")
                return False
            
            # 重新加密
            encrypt_cmd = ["age", "-o", age_file]
            for r in recipients:
                encrypt_cmd.extend(["-r", r])
            encrypt_cmd.append(tmp_path)
            
            subprocess.run(encrypt_cmd, check=True)
            print(f"文件已重新加密: {age_file}")
            return True
            
        finally:
            # 清理临时文件
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    def generate_key(self, key_type, name):
        """生成新的密钥对"""
        if key_type not in ["user", "host"]:
            print(f"错误: 无效的密钥类型 '{key_type}'，支持: user, host", file=sys.stderr)
            return False
            
        # 创建临时目录
        with tempfile.TemporaryDirectory() as tmp_dir:
            key_file = os.path.join(tmp_dir, f"{key_type}_{name}_key")
            
            # 生成密钥
            try:
                subprocess.run(["age-keygen", "-o", key_file], check=True)
                
                # 读取公钥
                with open(key_file, 'r') as f:
                    lines = f.readlines()
                    pubkey = None
                    for line in lines:
                        if not line.startswith('#'):
                            pubkey = line.strip()
                            break
                
                if not pubkey:
                    print("错误: 无法获取公钥", file=sys.stderr)
                    return False
                
                # 设置默认私钥路径
                if key_type == "user":
                    identity_path = f"/home/{name}/.ssh/id_age"
                else:
                    identity_path = f"/etc/ssh/ssh_{name}_age_key"
                
                # 添加到secrets.nix
                success = self.add_key(key_type, name, pubkey, identity_path)
                
                if success:
                    # 复制私钥到目标位置
                    print(f"密钥对生成成功！公钥已添加到secrets.nix")
                    print(f"私钥保存在: {key_file}")
                    print(f"请将私钥复制到目标位置: {identity_path}")
                    
                    # 复制私钥
                    response = input(f"是否显示私钥内容? (y/N): ")
                    if response.lower() == 'y':
                        with open(key_file, 'r') as f:
                            print(f.read())
                    
                    return True
                return False
                
            except subprocess.CalledProcessError as e:
                print(f"生成密钥失败: {e}", file=sys.stderr)
                return False

    def rekey_age_file(self, age_file, new_recipients, identity=None):
        """更改机密文件的接收者，支持密钥组"""
        # 类似于edit，但使用新的接收者
        if not os.path.exists(age_file):
            print(f"错误: 文件 '{age_file}' 不存在", file=sys.stderr)
            return False
            
        # 获取秘密映射
        secret_name = os.path.basename(age_file)
        
        # 创建临时文件并设置权限
        tmp = tempfile.NamedTemporaryFile(delete=False)
        tmp_path = tmp.name
        tmp.close()
        os.chmod(tmp_path, 0o600)
        
        try:
            # 解密到临时文件
            decrypt_cmd = ["age", "--decrypt"]
            if identity:
                decrypt_cmd.extend(["-i", identity])
            decrypt_cmd.extend(["-o", tmp_path, age_file])
            
            try:
                subprocess.run(decrypt_cmd, check=True)
            except subprocess.CalledProcessError:
                print("解密失败。尝试其他私钥...", file=sys.stderr)
                # 尝试默认路径
                default_identities = [
                    os.path.expanduser("~/.ssh/id_ed25519"),
                    "/etc/ssh/ssh_host_ed25519_key"
                ]
                decrypted = False
                for ident in default_identities:
                    if os.path.exists(ident):
                        try:
                            decrypt_cmd = ["age", "--decrypt", "-i", ident, "-o", tmp_path, age_file]
                            subprocess.run(decrypt_cmd, check=True)
                            decrypted = True
                            print(f"使用密钥 {ident} 解密成功")
                            break
                        except subprocess.CalledProcessError:
                            continue
                
                if not decrypted:
                    print("无法解密文件。请提供有效的私钥。", file=sys.stderr)
                    os.unlink(tmp_path)
                    return False
            
            # 展开密钥组
            real_recipients = self.expand_recipients(new_recipients)
            
            # 重新加密
            encrypt_cmd = ["age", "-o", age_file]
            for r in real_recipients:
                encrypt_cmd.extend(["-r", r])
            encrypt_cmd.append(tmp_path)
            
            subprocess.run(encrypt_cmd, check=True)
            print(f"文件已使用新接收者重新加密: {age_file}")
            
            # 提示更新secrets.nix
            print("警告: 您需要更新secrets.nix中的接收者配置")
            print("建议在secretMappings中更新以下内容:")
            recipients_str = ' '.join(new_recipients)
            print(f'  "{secret_name}" = {{')
            print(f'    recipients = [ {recipients_str} ];')
            print('    ...')
            print('  };')
            
            return True
            
        finally:
            # 清理临时文件
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)


def main():
    """主程序入口"""
    parser = argparse.ArgumentParser(description="密钥管理与机密文件工具")
    parser.add_argument("--dry-run", action="store_true", help="模拟执行，不实际更改文件")
    parser.add_argument("--yes", action="store_true", help="自动确认所有提示")
    subparsers = parser.add_subparsers(dest="command", help="命令")
    
    # 列出密钥
    list_parser = subparsers.add_parser("list", help="列出密钥或机密文件")
    list_parser.add_argument("type", choices=["keys", "secrets", "all"], help="列出类型")
    list_parser.add_argument("--filter", choices=["all", "users", "hosts", "groups"], 
                           default="all", help="密钥过滤器")
    
    # 添加密钥
    add_key_parser = subparsers.add_parser("add-key", help="添加新密钥")
    add_key_parser.add_argument("type", choices=["user", "host"], help="密钥类型")
    add_key_parser.add_argument("name", help="名称(用户名或主机名)")
    add_key_parser.add_argument("key", help="SSH公钥内容")
    add_key_parser.add_argument("--path", help="私钥路径(可选)")
    
    # 移除密钥
    remove_key_parser = subparsers.add_parser("remove-key", help="移除密钥")
    remove_key_parser.add_argument("type", choices=["user", "host"], help="密钥类型")
    remove_key_parser.add_argument("name", help="名称(用户名或主机名)")
    
    # 生成密钥
    generate_parser = subparsers.add_parser("generate", help="生成新密钥对")
    generate_parser.add_argument("type", choices=["user", "host"], help="密钥类型")
    generate_parser.add_argument("name", help="名称(用户名或主机名)")
    
    # 添加映射
    add_mapping_parser = subparsers.add_parser("add-mapping", help="添加新的机密映射")
    add_mapping_parser.add_argument("name", help="机密名称(.age文件)")
    add_mapping_parser.add_argument("recipients", help="接收者(格式: keyGroups.xxx)")
    add_mapping_parser.add_argument("target", help="目标路径")
    add_mapping_parser.add_argument("owner", help="所有者")
    add_mapping_parser.add_argument("group", help="组")
    add_mapping_parser.add_argument("--mode", default="600", help="权限模式(默认: 600)")
    
    # 加密文件
    encrypt_parser = subparsers.add_parser("encrypt", help="加密文件")
    encrypt_parser.add_argument("file", help="要加密的文件")
    encrypt_parser.add_argument("--recipients", nargs='+', required=True, help="接收者公钥")
    encrypt_parser.add_argument("--output", help="输出文件(默认: 输入文件名+.age)")
    
    # 编辑机密
    edit_parser = subparsers.add_parser("edit", help="编辑机密文件")
    edit_parser.add_argument("file", help=".age文件")
    edit_parser.add_argument("--identity", help="私钥路径(可选)")
    
    # 更改接收者
    rekey_parser = subparsers.add_parser("rekey", help="更改机密文件的接收者")
    rekey_parser.add_argument("file", help=".age文件")
    rekey_parser.add_argument("--recipients", nargs='+', required=True, help="新接收者公钥")
    rekey_parser.add_argument("--identity", help="私钥路径(可选)")
    
    # 检查一致性
    subparsers.add_parser("check", help="检查密钥和机密文件一致性")
    
    args = parser.parse_args()
    
    # 创建对象
    secret_ctl = SecretCtl(dry_run=args.dry_run, yes=args.yes)
    
    # 根据命令执行操作
    if args.command == "list":
        if args.type == "keys":
            secret_ctl.list_keys(args.filter)
        elif args.type == "secrets":
            secret_ctl.list_secrets()
        else:
            secret_ctl.list_keys()
            print("\n" + "-" * 50 + "\n")
            secret_ctl.list_secrets()
    
    elif args.command == "add-key":
        secret_ctl.add_key(args.type, args.name, args.key, args.path)
    
    elif args.command == "remove-key":
        secret_ctl.remove_key(args.type, args.name)
    
    elif args.command == "generate":
        secret_ctl.generate_key(args.type, args.name)
    
    elif args.command == "add-mapping":
        secret_ctl.add_secret_mapping(args.name, args.recipients, args.target, args.owner, args.group, args.mode)
    
    elif args.command == "encrypt":
        secret_ctl.encrypt_file(args.file, args.recipients, args.output)
    
    elif args.command == "edit":
        secret_ctl.decrypt_edit_reencrypt(args.file, args.identity)
    
    elif args.command == "rekey":
        secret_ctl.rekey_age_file(args.file, args.recipients, args.identity)
    
    elif args.command == "check":
        secret_ctl.check_consistency()
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()