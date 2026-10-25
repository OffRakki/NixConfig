{
  virtualisation.oci-containers.containers.ollama = {
    image = "docker.io/ollama/ollama:0.33.1@sha256:075246f72d4109385b4a01c3ac8e9cbd26a0bcb21cd7aa30edbccd24e1b3180c";
    devices = ["nvidia.com/gpu=all"];
    ports = ["127.0.0.1:11434:11434"];
    volumes = ["ollama:/root/.ollama"];
  };

  systemd.services.podman-ollama = {
    after = ["nvidia-container-toolkit-cdi-generator.service"];
    requires = ["nvidia-container-toolkit-cdi-generator.service"];
  };

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = 8090;
    openFirewall = true;
    environment.OLLAMA_BASE_URL = "http://127.0.0.1:11434";
  };
}
