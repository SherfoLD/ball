#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ball-tests.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc Ball/BallPhysicsEngine.swift Ball/DockUtils.swift Tests/PhysicsTestBall.swift Tests/main.swift -o "$BUILD_DIR/tests"
"$BUILD_DIR/tests"
