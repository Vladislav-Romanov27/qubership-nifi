#!/bin/bash
# Runs nifi-upgrade-skill through opencode to upgrade Apache NiFi in the working tree.
# The agent only changes files: committing, pushing, and opening the pull request are left
# to the caller. The agent writes its final report, which becomes the pull request
# description, to REPORT_FILE.
#
# Environment:
#   NIFI_VERSION       target Apache NiFi version, for example 2.13.0
#   NIFI_DIGEST        digest of the apache/nifi:<NIFI_VERSION> image, sha256:<hex>
#   REPORT_FILE        report path, upgrade-temp-data/pr-body.md by default
#   OPENAI_API_KEY     key for the openai provider of the model set in .opencode/opencode.json

set -euo pipefail

: "${NIFI_VERSION:?NIFI_VERSION is not set}"
: "${NIFI_DIGEST:?NIFI_DIGEST is not set}"
REPORT_FILE="${REPORT_FILE:-upgrade-temp-data/pr-body.md}"

mkdir -p "$(dirname "$REPORT_FILE")"

PROMPT=$(
    cat <<EOF
Upgrade Apache NiFi to version ${NIFI_VERSION} by following the nifi-upgrade-skill skill.
Load it with the skill tool (@nifi-upgrade-skill) and run its steps in order.

Inputs for step 1:
- Target NiFi version: ${NIFI_VERSION}
- SHA256 hash: ${NIFI_DIGEST}

This run is non-interactive in GitHub Actions, and nobody can answer questions. Follow these rules:
- Do not ask questions. Where the skill tells you to ask the user, make no change and record the item in the report.
- In step 12, build only the display-name renames in dictionary.yaml and list the deleted properties
  under "Tasks for the reviewer", as the step says for a GitHub Actions run.
- Skip step 14 (release notes) and list it under "Tasks for the reviewer" in the report.
- Add --batch-mode --no-transfer-progress -Dgpg.skip=true to every mvn command. The runner has no GPG key,
  so a build that reaches the verify phase fails without -Dgpg.skip=true.
- Do not run git commit or git push, and do not create branches or pull requests. Leave the changes in the working tree.
- Do not change files under .github/ or .agent-tools/.

When you finish, write the final report in GitHub-flavored Markdown to ${REPORT_FILE}.
The report becomes the pull request description. Start it with a one-paragraph summary, then include:
- the files changed and the reason for each change;
- every Migration Guidance item classified as applied, not applicable, or user action required, as step 9 requires;
- the build and test results from step 10;
- a "Tasks for the reviewer" section with the deleted properties from step 12, step 14, and every item that needs
  user action.
EOF
)

opencode run --auto "$PROMPT"

if [ ! -s "$REPORT_FILE" ]; then
    echo "::warning::The agent did not write the report to $REPORT_FILE."
fi
