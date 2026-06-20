#!/usr/bin/env bash

workspace=${1:?Usage: wkspcSwitch.sh <workspace_number>}
monitor=$(hyprctl workspaces -j | jq -r --argjson id "$workspace" '.[] | select(.id == $id) | .monitor // empty')

[ -n "$monitor" ] && hyprctl dispatch focusmonitor "$monitor"
hyprctl dispatch workspace "$workspace"
