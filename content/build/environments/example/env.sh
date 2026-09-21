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
# Production approval is NOT decided here. It is decided by the environment's
# `class` in .claude/environments.json — 10-preflight.sh runs the approval
# gate when ENV_CLASS is prod. This flag was read by zero code from the day
# it was written; the comment claiming 10-preflight checked it was false.
# Kept only so existing env.sh files that set it do not look broken.
export REQUIRES_APPROVAL=false        # vestigial — see .claude/environment-rules.md

# ─── WARNING: this file is SOURCED into the deploy driver's own shell ────────
#
# build/deploy runs `source build/environments/<env>/env.sh`. Anything assigned
# here becomes a variable in the driver itself, not just in your deploy script.
#
# NEVER assign any of these:
#
#   SKIP_TESTS   SKIP_GATES   DRY_RUN   INTENT   ENV
#       Assigning these silently disarms the pipeline for this environment,
#       permanently and invisibly. SKIP_TESTS=true here once shipped a failing
#       test to production at exit 0. The driver now refuses --skip-tests at
#       prod class, which catches this too — but do not write the pattern.
#
#   BUILD_DIR    PROJECT_DIR
#       These resolve every gate the driver invokes. Reassigning BUILD_DIR
#       redirected class-guard to a stub and allowed a deploy into production.
#       The driver now re-derives both after sourcing this file.
#
# Use this file for application configuration — APP_ENV, API_URL, region,
# credentials sourced from your secret store. Export what your deploy.sh needs.
