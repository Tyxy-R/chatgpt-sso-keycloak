#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p providers
docker run --rm \
  -v "$PWD/provider-auto-create:/workspace" \
  -w /workspace \
  maven:3.9-eclipse-temurin-21-alpine \
  mvn -q -DskipTests package

cp provider-auto-create/target/auto-create-username-password-form-1.0.0.jar providers/
echo "Built providers/auto-create-username-password-form-1.0.0.jar"
