# Email is piped through stdin, never interpolated into a shell command.
if [[ $# -ne 1 || ! "$1" =~ ^[[:xdigit:]]{1,128}$ ]]; then
  printf 'Usage: pi-mail <hexadecimal-session-id> (prompt on stdin)\n' >&2
  exit 2
fi

cd /home/rakki/sync/geral/Ciel/Mailbox
# SSH sessions do not reliably inherit the logged-in desktop's D-Bus address.
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID/bus"
exec pi --print --session-id "$1" \
  --no-approve --no-context-files --no-skills --no-prompt-templates \
  --no-extensions --extension "@notifyExtension@" \
  --tools desktop_notify
