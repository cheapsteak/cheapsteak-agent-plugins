#!/usr/bin/env bash
# lib.sh — multi-signal helpers for monitor recipes.
#
# Sourced automatically by run-recipe.sh before the recipe.
# All helpers read $cur and $prev (JSON blobs set by the runtime) and emit
# tagged blocks to stdout from the recipe's EMIT function. Each helper is
# silent when nothing changed.
#
# Multi-signal recipe shape:
#   FETCH()     produces a JSON blob batching every signal in one call
#   EXTRACT()   is cat (the blob IS the value to diff)
#   WAKE_WHEN() is [[ "$cur" != "$prev" ]]
#   EMIT()      calls these helpers, one per signal

# diff_changed TAG '<jq_path>'
#   Emits TAG plus WAS/NOW lines when the jq-extracted value differs
#   between $prev and $cur. Treats missing paths as empty string.
diff_changed() {
  local tag="$1" path="$2"
  local pv cv
  pv="$(jq -r "${path} // \"\"" <<< "$prev" 2>/dev/null)"
  cv="$(jq -r "${path} // \"\"" <<< "$cur"  2>/dev/null)"
  if [[ "$pv" != "$cv" ]]; then
    printf '%s\n' "$tag"
    printf '%s_WAS=%s\n' "$tag" "$pv"
    printf '%s_NOW=%s\n' "$tag" "$cv"
  fi
}

# diff_new_ids TAG '<array_path>' '<id_jq>'
#   Emits TAG and a JSON array of items in $cur's array that are NOT in
#   $prev's array, matching by the jq-derived id. Silent when set unchanged.
#
#   Example: diff_new_ids NEW_COMMENTS '.comments' '.id'
diff_new_ids() {
  local tag="$1" path="$2" id_jq="$3"
  local prev_ids cur_ids new_ids new_items
  prev_ids="$(jq -c "[ ${path}[]? | ${id_jq} ]" <<< "$prev" 2>/dev/null || echo '[]')"
  cur_ids="$(jq -c "[ ${path}[]? | ${id_jq} ]"  <<< "$cur"  2>/dev/null || echo '[]')"
  new_ids="$(jq -nc --argjson p "$prev_ids" --argjson c "$cur_ids" '$c - $p')"
  if [[ -n "$new_ids" && "$new_ids" != "[]" ]]; then
    printf '%s\n' "$tag"
    new_items="$(jq -c --argjson new "$new_ids" "[ ${path}[]? | select((${id_jq}) | IN(\$new[])) ]" <<< "$cur" 2>/dev/null || echo '[]')"
    printf '%s_ITEMS=%s\n' "$tag" "$new_items"
  fi
}

# diff_bucket_fail TAG '<checks_path>'
#   Emits TAG, the failed names (comma-separated), and bucket counts when:
#     - $cur has at least one item with .bucket == "fail" AND
#     - the set of failing names differs from $prev's failing set.
#   Designed for `gh pr checks --json bucket,name` output shape.
diff_bucket_fail() {
  local tag="$1" path="$2"
  local cur_failed prev_failed
  cur_failed="$(jq -c  "[ ${path}[]? | select(.bucket == \"fail\") | .name ]" <<< "$cur"  2>/dev/null || echo '[]')"
  prev_failed="$(jq -c "[ ${path}[]? | select(.bucket == \"fail\") | .name ]" <<< "$prev" 2>/dev/null || echo '[]')"
  if [[ "$cur_failed" != "[]" && "$cur_failed" != "$prev_failed" ]]; then
    local n_pass n_pending n_fail n_skip
    n_pass=$(jq    "[ ${path}[]? | select(.bucket == \"pass\")    ] | length" <<< "$cur" 2>/dev/null || echo 0)
    n_pending=$(jq "[ ${path}[]? | select(.bucket == \"pending\") ] | length" <<< "$cur" 2>/dev/null || echo 0)
    n_fail=$(jq    "[ ${path}[]? | select(.bucket == \"fail\")    ] | length" <<< "$cur" 2>/dev/null || echo 0)
    n_skip=$(jq    "[ ${path}[]? | select(.bucket == \"skipping\" or .bucket == \"cancel\") ] | length" <<< "$cur" 2>/dev/null || echo 0)
    printf '%s\n' "$tag"
    printf '%s_NAMES=%s\n'  "$tag" "$(jq -r 'join(",")' <<< "$cur_failed")"
    printf '%s_COUNTS=pass=%s pending=%s fail=%s skip=%s\n' "$tag" "$n_pass" "$n_pending" "$n_fail" "$n_skip"
  fi
}
