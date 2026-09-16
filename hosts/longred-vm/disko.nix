# Disk layout for the longred-vm KVM guest.
#
# The guest boots with legacy BIOS: the virtualization host runs it on
# SeaBIOS/Q35 without UEFI firmware, so the disk needs a BIOS boot partition
# for GRUB's core image rather than an EFI system partition. The layout is
# therefore one 1 MiB EF02 partition followed by a single ext4 root.
#
# nixos-anywhere runs this through disko; `boot.loader.grub.device` in
# ./configuration.nix points at the whole disk.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
