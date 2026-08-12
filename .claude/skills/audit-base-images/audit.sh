#!/usr/bin/env bash
#
# audit-base-images - Check if a GitHub repo uses the shared Renovate
# //base-images preset for any AIPCC base image pins it contains.
#
# Usage:
#   audit.sh <owner/repo> [--json] [--paths path1 path2 ...]
#   audit.sh --org <org-name> [--json]
#
# In single-repo mode, --paths skips the GitHub code search API and uses
# the given file paths directly.
#
# In --org mode, performs a single code search against the entire org,
# then audits each discovered repo with the pre-fetched paths. This
# avoids per-repo search calls that trigger API rate limits.
#
# Exit codes: 0 = all compliant, 1 = any non-compliant, 2 = usage error
#
# Requires: gh, jq

set -euo pipefail

IMAGE_PATTERN='quay\.io/aipcc/base-images/|registry\.redhat\.io/rhai(-early-access)?/base-image-'
DOCS_PATTERN='\.(md|txt|rst|py|rb|js|ts)$'
BUILDABLE_NAME_PATTERN='^(Dockerfile|Containerfile)'
BUILDABLE_EXT_PATTERN='\.(conf|yml|yaml)$'

# ── Per-repo audit function ──────────────────────────────────────────────

audit_repo() {
    local repo="$1"
    local json_output="$2"
    shift 2
    local provided_paths=("$@")

    # Step 1: find files referencing AIPCC base images
    local hits
    if [[ ${#provided_paths[@]} -gt 0 ]]; then
        hits=$(printf '%s\n' "${provided_paths[@]}" | jq -R -s 'split("\n") | map(select(. != ""))')
    else
        hits="[]"
        local q items
        for q in \
            "repo:$repo \"aipcc/base-images\"" \
            "repo:$repo \"registry.redhat.io/rhai\" base-image"; do
            items=$(gh api -X GET search/code -f "q=$q" -f per_page=100 --paginate \
                --jq '[.items[] | .path]' 2>/dev/null | jq -s 'add // []') || continue
            hits=$(echo "$hits $items" | jq -s 'add | unique')
        done
    fi

    # Step 2: filter to buildable files, find pinned lines
    local default_branch
    default_branch=$(gh api "repos/$repo" --jq '.default_branch' 2>/dev/null || echo "main")
    local files="[]"

    local path content pins file_pins match lineno line
    for path in $(echo "$hits" | jq -r '.[]'); do
        echo "$path" | grep -qiE "$DOCS_PATTERN" && continue
        basename "$path" | grep -qiE "$BUILDABLE_NAME_PATTERN" \
            || echo "$path" | grep -qiE "$BUILDABLE_EXT_PATTERN" \
            || continue

        content=$(gh api "repos/$repo/contents/$path?ref=$default_branch" \
            --jq '.content' 2>/dev/null | base64 -d 2>/dev/null) || continue

        pins=$(echo "$content" \
            | grep -nE "$IMAGE_PATTERN" \
            | grep -vE '^\s*[0-9]+:\s*#' \
            || true)

        [[ -z "$pins" ]] && continue

        file_pins="[]"
        while IFS= read -r match; do
            lineno="${match%%:*}"
            line="${match#*:}"
            line=$(echo "$line" | sed 's/^[[:space:]]*//')
            file_pins=$(echo "$file_pins" | jq \
                --arg l "$lineno" --arg c "$line" \
                --arg u "https://github.com/$repo/blob/$default_branch/$path#L$lineno" \
                '. + [{line: ($l | tonumber), content: $c, url: $u}]')
        done <<< "$pins"

        files=$(echo "$files" | jq --arg p "$path" --argjson pins "$file_pins" \
            '. + [{path: $p, pins: $pins}]')
    done

    local pin_count
    pin_count=$(echo "$files" | jq 'length')

    # Step 3: check Renovate config for //base-images preset
    local renovate_status="none"
    local renovate_file=""
    local f rc
    for f in renovate.json renovate.json5 .renovaterc .renovaterc.json \
             .github/renovate.json .github/renovate.json5; do
        rc=$(gh api "repos/$repo/contents/$f" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null) || true
        [[ -z "$rc" ]] && continue
        renovate_file="$f"
        if echo "$rc" | grep -qE 'opendatahub-io/renovate-config.*//base-images'; then
            renovate_status="compliant"
        else
            renovate_status="missing_preset"
        fi
        break
    done

    # Step 4: verdict
    local compliant=true
    if [[ "$pin_count" -gt 0 && "$renovate_status" != "compliant" ]]; then
        compliant=false
    fi

    # Output
    if [[ "$json_output" == "true" ]]; then
        jq -n \
            --arg repo "$repo" \
            --argjson compliant "$compliant" \
            --arg renovate_status "$renovate_status" \
            --arg renovate_file "$renovate_file" \
            --argjson files "$files" \
            '{repo: $repo, compliant: $compliant, renovate_status: $renovate_status, renovate_file: $renovate_file, files: $files}'
        $compliant && return 0 || return 1
    fi

    if [[ "$pin_count" -eq 0 ]]; then
        echo "PASS  $repo (no AIPCC base image references in buildable files)"
        return 0
    fi

    if $compliant; then
        echo "PASS  $repo"
        return 0
    fi

    local reason
    case "$renovate_status" in
        none)            reason="No Renovate configuration found" ;;
        missing_preset)  reason="Renovate config ($renovate_file) does not extend //base-images preset" ;;
    esac

    echo "FAIL  $repo"
    echo "      $reason"
    echo ""
    echo "      Pinned base images:"
    echo "$files" | jq -r '.[] | .pins[] | "        \(.url)\n          \(.content)"'
    return 1
}

# ── Org-wide audit function ──────────────────────────────────────────────

audit_org() {
    local org="$1"
    local json_output="$2"

    # Single discovery pass: 2 API calls for the entire org
    local all_hits=""
    local q
    for q in \
        "org:$org \"aipcc/base-images\"" \
        "org:$org \"registry.redhat.io/rhai\" base-image"; do
        all_hits="$all_hits
$(gh api -X GET search/code -f "q=$q" -f per_page=100 --paginate \
    --jq '.items[] | "\(.repository.full_name)\t\(.path)"' 2>/dev/null || true)"
    done
    all_hits=$(echo "$all_hits" | sort -u | grep -v renovate-config | grep -v '^$')

    if [[ -z "$all_hits" ]]; then
        echo "No AIPCC base image references found in org $org"
        return 0
    fi

    # Group paths by repo and audit each
    local prev_repo="" repo path
    local paths=()
    local any_failed=false

    while IFS=$'\t' read -r repo path; do
        if [[ "$repo" != "$prev_repo" && -n "$prev_repo" ]]; then
            audit_repo "$prev_repo" "$json_output" "${paths[@]}" || any_failed=true
            [[ "$json_output" != "true" ]] && echo ""
            paths=()
        fi
        prev_repo="$repo"
        paths+=("$path")
    done <<< "$all_hits"

    if [[ -n "$prev_repo" ]]; then
        audit_repo "$prev_repo" "$json_output" "${paths[@]}" || any_failed=true
    fi

    $any_failed && return 1 || return 0
}

# ── Argument parsing ─────────────────────────────────────────────────────

MODE="repo"
REPO="${1:-}"
JSON_OUTPUT=false
PROVIDED_PATHS=()

if [[ -z "$REPO" || "$REPO" == "--help" || "$REPO" == "-h" ]]; then
    sed -n '2,/^$/s/^# //p' "$0"
    exit 0
fi

if [[ "$REPO" == "--org" ]]; then
    MODE="org"
    shift
    REPO="${1:-}"
    if [[ -z "$REPO" ]]; then
        echo "Error: --org requires an organization name" >&2
        exit 2
    fi
fi

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_OUTPUT=true; shift ;;
        --paths) shift; while [[ $# -gt 0 && "$1" != --* ]]; do PROVIDED_PATHS+=("$1"); shift; done ;;
        *) shift ;;
    esac
done

# ── Main ─────────────────────────────────────────────────────────────────

if [[ "$MODE" == "org" ]]; then
    audit_org "$REPO" "$JSON_OUTPUT"
else
    audit_repo "$REPO" "$JSON_OUTPUT" "${PROVIDED_PATHS[@]}"
fi
