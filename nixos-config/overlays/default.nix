{ inputs, ... }:
{
  additions = final: _prev: import ../pkgs final.pkgs;
  # 在这里定义你的自定义覆盖层
  # 例如:
  # myPackage = prev.myPackage.override { ... };
}
