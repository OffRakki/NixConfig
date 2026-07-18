root=$(jj root) || {
  echo "piw: not in a jj repository" >&2
  exit 1
}

# `jj root` does not snapshot pending filesystem changes. Freeze them before
# branching the temporary workspace so both workspaces share the same base.
jj -R "$root" util snapshot --quiet
invoking_change=$(jj -R "$root" log --no-graph -r @ -T change_id)
invoking_commit=$(jj -R "$root" log --no-graph -r @ -T commit_id)
workspace_name="pi-$(date +%s)-$$"
workspace_base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/pi-jj-workspaces/$(basename "$root")"
workspace_path="$workspace_base/$workspace_name"
workspace_added=false

# shellcheck disable=SC2329 # Invoked indirectly by trap.
cleanup() {
  if [[ $workspace_added != true ]]; then
    return
  fi

  if jj -R "$root" workspace forget "$workspace_name"; then
    case "$workspace_path" in
      "$workspace_base"/*) rm -rf -- "$workspace_path" ;;
      *) echo "piw: refusing to remove unexpected path: $workspace_path" >&2 ;;
    esac
  else
    echo "piw: failed to forget workspace $workspace_name; keeping $workspace_path" >&2
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workspace_base"
if [[ -e $workspace_path ]]; then
  echo "piw: workspace path already exists: $workspace_path" >&2
  exit 1
fi

jj -R "$root" workspace add "$workspace_path" \
  --name "$workspace_name" \
  --revision "$invoking_change"
workspace_added=true
echo "piw: workspace $workspace_name ready at $workspace_path" >&2

set +e
(
  cd "$workspace_path"
  pi "$@"
)
pi_status=$?
set -e

# Snapshot Pi's edits before inspecting or forgetting its working copy.
jj -R "$workspace_path" util snapshot --quiet
jj -R "$root" workspace update-stale

if [[ -z $(jj -R "$workspace_path" diff --from "$invoking_commit" --to @ --summary) ]]; then
  echo "piw: no changes; removing workspace $workspace_name" >&2
  exit "$pi_status"
fi

workspace_head=$(jj -R "$workspace_path" log --no-graph -r @ -T change_id)
printf '\npiw: changes produced in %s:\n\n' "$workspace_name" >&2
jj -R "$workspace_path" diff --from "$invoking_commit" --to @

printf '\n' >&2
if read -r -p "Integrate changes into the invoking change? [y/N] " confirm \
  && [[ $confirm =~ ^[Yy]$ ]]; then
  if [[ -z $(jj -R "$root" log --no-graph -r "$invoking_change & ::$workspace_head" -T change_id) ]]; then
    echo "piw: workspace history diverged; leaving changes separate" >&2
  else
    jj -R "$root" squash \
      --from "$invoking_change..$workspace_head" \
      --into "$invoking_change" \
      --use-destination-message
    jj -R "$root" workspace update-stale
    echo "piw: integrated changes into the invoking change" >&2
  fi
else
  imported_change=$(
    jj -R "$workspace_path" log --no-graph \
      -r 'heads(first_ancestors(@) & ~empty())' -T change_id
  )
  echo "piw: left change $imported_change separate for later review" >&2
fi

exit "$pi_status"
