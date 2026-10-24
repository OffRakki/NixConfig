{
  provider = "codex";
  model = "gpt-6.1-sol";
  effort = "medium";
  theme = "dark";
  tint = "rose";
  notify = "off";
  session_retention_days = 0;
  # Keep opening the pilot independent of catalog network requests.
  catalog.refresh = "0";
  bash = {
    timeout = "10m";
    timeout_max = "30m";
  };
  task.max_running = 4;
}
