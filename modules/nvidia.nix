{ config, lib, pkgs, ... }: {
  # Use proprietary NVIDIA driver and enable PRIME offload for hybrid graphics
  services.xserver.videoDrivers = [ "nvidia" ];

  # Modern graphics stack (replaces old hardware.opengl)
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32-bit userspace for Steam/Proton, etc.
    extraPackages = with pkgs; [
      # Intel iGPU VA-API (primary display)
      intel-media-driver
      vaapiVdpau
      libvdpau-va-gl
      # Optional: VA-API on NVIDIA (newer drivers)
      nvidia-vaapi-driver
    ];
  };

  hardware.nvidia = {
    # Enable kernel modesetting and NVIDIA settings
    modesetting.enable = true; # sets nvidia_drm.modeset=1
    nvidiaSettings = true;

    # Use proprietary driver (recommended for PRIME/Wayland)
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Power management for laptops
    powerManagement.enable = true;
    powerManagement.finegrained =
      lib.mkDefault true; # may require recent kernels/drivers

    # PRIME render offload: Intel as primary, NVIDIA as offload GPU
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true; # provides `nvidia-offload` wrapper
      };

      # NOTE: Bus IDs are common defaults; verify with `lspci | grep -E "VGA|3D"`
      # Intel iGPU: 0000:00:02.0  =>  PCI:0:2:0 (from your output)
      # NVIDIA dGPU: 0000:32:00.0 =>  PCI:32:0:0 (from your output)
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:32:0:0";
    };
  };

  # Wayland/GBM friendly defaults for NVIDIA
  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # Enable VA-API on NVIDIA if using nvidia-vaapi-driver
    LIBVA_DRIVER_NAME = "nvidia";
  };
}
