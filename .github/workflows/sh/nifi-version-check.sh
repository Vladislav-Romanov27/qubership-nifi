#!/bin/bash
# Finds the Apache NiFi version to upgrade to and writes version, digest, and branch
# to $GITHUB_OUTPUT. Outside GitHub Actions, where GITHUB_OUTPUT is unset, it prints them.
# All three values are empty when there is nothing to upgrade to.
#
# A version qualifies when its apache/nifi Docker Hub tag is X.Y.Z with the current
# major version, is newer than the current version, and was pushed at least
# MIN_AGE_DAYS ago. The highest qualifying version is chosen. It is skipped when a pull
# request from its branch exists in any state: closing one without a merge skips the version.
#
# Environment:
#   CURRENT_VERSION    current version; read from nifi.version in pom.xml when unset
#   MIN_AGE_DAYS       minimum tag age in days, 7 by default
#   GH_TOKEN           token for the GitHub CLI
#   GITHUB_REPOSITORY  owner/name of the repository; gh uses the git remote when unset
#   GITHUB_OUTPUT      file for the step outputs; set by GitHub Actions

set -euo pipefail

MIN_AGE_DAYS="${MIN_AGE_DAYS:-7}"
TAGS_URL="https://hub.docker.com/v2/repositories/apache/nifi/tags?page_size=100"

write_output() {
    local version="$1" digest="$2" branch="$3"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        {
            echo "version=$version"
            echo "digest=$digest"
            echo "branch=$branch"
        } >>"$GITHUB_OUTPUT"
    else
        echo "version=$version"
        echo "digest=$digest"
        echo "branch=$branch"
    fi
}

read_current_version() {
    local version
    version=$(sed -n 's:.*<nifi\.version>\([^<]*\)</nifi\.version>.*:\1:p' pom.xml | head -n 1)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "::error::Cannot read nifi.version from pom.xml, found '$version'." >&2
        return 1
    fi
    echo "$version"
}

# Prints every apache/nifi tag as one JSON object per line, following pagination.
fetch_tags() {
    local url="$TAGS_URL" page
    while [ -n "$url" ] && [ "$url" != "null" ]; do
        page=$(curl --fail --silent --show-error --retry 3 "$url")
        echo "$page" | jq -c '.results[]'
        url=$(echo "$page" | jq -r '.next')
    done
}

# Reads tags from stdin and prints {version, digest, pushed} for the newest
# qualifying version, or {} when none qualifies.
select_version() {
    local current="$1"
    jq -s -c \
        --arg current "$current" \
        --argjson min_age_days "$MIN_AGE_DAYS" '
        def semver: split(".") | map(tonumber);
        ($current | semver) as $cur
        | (now - $min_age_days * 86400) as $cutoff
        | map(select(
            (.name | test("^[0-9]+[.][0-9]+[.][0-9]+$"))
            and .tag_last_pushed != null
            and .digest != null
          ))
        | map(. + {semver: (.name | semver)})
        | map(select(
            .semver[0] == $cur[0]
            and .semver > $cur
            and (.tag_last_pushed | sub("[.][0-9]+Z$"; "Z") | fromdateiso8601) <= $cutoff
          ))
        | max_by(.semver)
        | if . == null then {} else {version: .name, digest: .digest, pushed: .tag_last_pushed} end
        '
}

# Prints "#<number> (<state>)" for each pull request from the branch, in any state.
find_pull_requests() {
    local branch="$1"
    local repo_args=()
    if [ -n "${GITHUB_REPOSITORY:-}" ]; then
        repo_args=(--repo "$GITHUB_REPOSITORY")
    fi
    gh pr list "${repo_args[@]}" --head "$branch" --state all \
        --json number,state --jq '.[] | "#\(.number) (\(.state))"'
}

main() {
    local current result version digest branch prs

    current="${CURRENT_VERSION:-}"
    if [ -z "$current" ]; then
        current=$(read_current_version)
    fi
    echo "Current Apache NiFi version: $current"

    result=$(fetch_tags | select_version "$current")
    version=$(echo "$result" | jq -r '.version // ""')
    digest=$(echo "$result" | jq -r '.digest // ""')
    if [ -z "$version" ]; then
        echo "No Apache NiFi version newer than $current was pushed at least $MIN_AGE_DAYS days ago."
        write_output "" "" ""
        return 0
    fi
    echo "Found Apache NiFi $version, pushed $(echo "$result" | jq -r '.pushed'), digest $digest."

    branch="feat/upgrade-nifi-to-$version"
    prs=$(find_pull_requests "$branch")
    if [ -n "$prs" ]; then
        echo "Pull requests from $branch already exist, skipping the update:"
        echo "$prs"
        write_output "" "" ""
        return 0
    fi

    write_output "$version" "$digest" "$branch"
}

main "$@"
