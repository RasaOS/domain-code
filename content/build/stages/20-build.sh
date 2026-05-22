#!/usr/bin/env bash
# 20-build.sh — produce the deployable artifact
#
# Project-specific. Replace the placeholder with the actual build command.
# Run /setup-deploy to fill this in interactively.
#
# Examples:
#   Web:        npm ci && npm run build
#   iOS:        xcodebuild archive -scheme MyApp -archivePath build/MyApp.xcarchive
#   Container:  docker build -t "$IMAGE_NAME:$DEPLOY_TAG" .
#   Python:     python -m build
#
# $1 = environment name

set -euo pipefail
ENV="${1:?missing environment}"

echo "TODO: configure 20-build.sh for this project."
echo "Run /setup-deploy or edit this file directly."
echo ""
echo "Env: $ENV"
echo "Tag: $DEPLOY_TAG"

# If your project has no build step (e.g. pure config repo, library that
# publishes at deploy time), replace the lines above with: exit 0
exit 1
