#!/usr/bin/env bash
# environments/<env>/env.sh — exports env vars for this environment
#
# This is the EXAMPLE / TEMPLATE. Copy this folder to environments/dev,
# environments/staging, environments/prod, etc. and customize per env.
#
# This file is sourced by build/deploy before stages run. Available to
# all stages and the env-specific deploy.sh as exported vars.
#
# Keep secrets OUT of this file — it's committed. Use CI variable groups,
# 1Password, or a secrets manager and inject at runtime.

# ─── Identity ──────────────────────────────────────────────────────────────
export ENVIRONMENT_NAME="example"
export DEPLOY_TARGET=""               # e.g. https://staging.mysite.com

# ─── Build / artifact identity ─────────────────────────────────────────────
export IMAGE_NAME=""                  # container projects
export REGISTRY=""                    # e.g. myacr.azurecr.io

# ─── Platform-specific (uncomment for your target) ─────────────────────────

# Firebase Hosting
# export FIREBASE_PROJECT="mysite-staging"

# Azure Kubernetes
# export AKS_CLUSTER="my-aks"
# export AKS_RESOURCE_GROUP="my-rg"
# export AKS_NAMESPACE="staging"

# iOS / TestFlight
# export SCHEME="MyApp"
# export ASC_KEY_ID="$ASC_KEY_ID"    # from CI / 1Password, not committed

# ─── Behavior flags ────────────────────────────────────────────────────────
export REQUIRES_APPROVAL=false        # set true for prod (10-preflight checks)
