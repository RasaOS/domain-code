#!/usr/bin/env bash
# 40-publish.sh — push the artifact to its target (registry, store, etc.)
#
# Project-specific. May be a no-op for projects whose deploy step does
# both publish + deploy in one shot (e.g. Firebase Hosting).
#
# Examples:
#   Container:  docker push "$REGISTRY/$IMAGE_NAME:$DEPLOY_TAG"
#   iOS:        xcodebuild -exportArchive  # export .ipa (if not done in build)
#   Web:        no-op (handled by deploy.sh)
#   npm pkg:    npm publish --access public
#
# $PUBLISH_TO holds this environment's registry cloud-stamp name (from
# .claude/environments.json), or is empty. Typical guard:
#   [[ -z "$PUBLISH_TO" ]] && { echo "no publish target"; exit 0; }
#
# $1 = environment name

set -euo pipefail
ENV="${1:?missing environment}"

# Default: no publish step. Customize as needed for the project.
echo "Publish step: no-op (PUBLISH_TO=${PUBLISH_TO:-unset}; configure in 40-publish.sh)"
exit 0
