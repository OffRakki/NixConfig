{
  config,
  ...
}: {
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;

    powerManagement = {
      # Required for reliable suspend/resume on Wayland: enables NVIDIA's
      # suspend/hibernate/resume systemd units and preserves VRAM allocations.
      enable = true;
      # Fine-grained power management is for PRIME/laptop offload setups.
      finegrained = false;
    };
    dynamicBoost.enable = false; # Dynamic Boost for laptops
    nvidiaPersistenced = true;
    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.

    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };
}
