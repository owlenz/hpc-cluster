#!/usr/bin/env bash

# hosts=$(nodels all | jq -R . | jq -s .)
hosts=$(printf '%s\n' cn1 cn2 xcatmn | jq -R . | jq -s .)
jq -n --argjson h "$hosts" '{all: {hosts: $h}, _meta: {hostvars: {}}}'
