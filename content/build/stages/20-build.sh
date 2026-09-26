#!/usr/bin/env bash
# 20-build.sh — produce the deployable artifact
#
# Project-specific. Replace the placeholder with the actual build command.
# Run /setup-deploy to fill this in interactively. This is the project's ONE
# build definition: ./build/build runs it (/build), and ./build/deploy ships
# what it recorded instead of running it again.
#
# THEN DECLARE WHAT IT PRODUCED — one line per output, appended to
# $BUILD_ARTIFACTS (always set). ./build/build fingerprints them, and staging
# and prod refuse a build whose outputs changed after it was tested. Keep the
# outputs in .gitignore: a build that dirties the tree fails.
#
# Examples:
#   Web:        npm ci && npm run build
#               echo "dist" >> "$BUILD_ARTIFACTS"
#   iOS:        xcodebuild archive -scheme MyApp -archivePath build/MyApp.xcarchive
#               echo "build/MyApp.xcarchive" >> "$BUILD_ARTIFACTS"
#   Container:  docker build -t "$IMAGE_NAME:$BUILD_TAG" .
#               echo "image=$(docker image inspect -f '{{.Id}}' "$IMAGE_NAME:$BUILD_TAG")" >> "$BUILD_ARTIFACTS"
#   Python:     python -m build
#               echo "dist" >> "$BUILD_ARTIFACTS"
#   Deploys that build from source themselves (no artifact):
#               echo "source=commit" >> "$BUILD_ARTIFACTS"
#
# $BUILD_TAG names this build — tag images with it; 40-publish pushes the
# same tag. $1 is the environment for an `./build/build --env=<e>` build (its
# env.sh is loaded), or "build" for an environment-neutral one: an
# environment-neutral build must not depend on env.sh variables.

set -euo pipefail
ENV="${1:?missing environment}"

echo "TODO: configure 20-build.sh for this project."
echo "Run /setup-deploy or edit this file directly."
echo ""
echo "Env: $ENV"
echo "Tag: $BUILD_TAG"

# If your project has no build step (e.g. pure config repo, library that
# publishes at deploy time), replace the lines above with: exit 0
exit 1
