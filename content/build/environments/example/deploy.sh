#!/usr/bin/env bash
# environments/<env>/deploy.sh — the actual deploy command for this env
#
# This is the EXAMPLE / TEMPLATE. Copy this folder per environment and
# replace the placeholder with the real deploy command(s).
#
# Available exported vars (set by build/deploy + env.sh):
#   $ENVIRONMENT, $DEPLOY_TAG, $DEPLOY_USER, $DEPLOY_TIMESTAMP
#   $PUBLISH_TO, $DEPLOY_TO — registry cloud-stamp targets for this env
#   $IMAGE_NAME, $REGISTRY, plus anything env.sh exports
#
# Examples by target:
#
# Firebase Hosting:
#   firebase deploy --only hosting --project "$FIREBASE_PROJECT"
#
# Azure Kubernetes (kubectl):
#   az aks get-credentials -n "$AKS_CLUSTER" -g "$AKS_RESOURCE_GROUP"
#   kubectl set image deployment/myapp myapp="$REGISTRY/$IMAGE_NAME:$DEPLOY_TAG" -n "$AKS_NAMESPACE"
#   kubectl rollout status deployment/myapp -n "$AKS_NAMESPACE"
#
# iOS / TestFlight:
#   xcrun altool --upload-app -f build/MyApp.ipa --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
#
# Static (S3 / CDN):
#   aws s3 sync dist/ "s3://$BUCKET" --delete
#   aws cloudfront create-invalidation --distribution-id "$CF_ID" --paths '/*'

set -euo pipefail

echo "TODO: configure deploy.sh for environment '$ENVIRONMENT'"
echo "Run /setup-deploy or edit this file directly."
exit 1
