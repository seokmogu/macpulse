#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
mkdir -p .build
xcrun swiftc -parse-as-library -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx14.0" \
  Sources/MacPulseCore/MetricSnapshot.swift Sources/MacPulseCore/MetricCollector.swift \
  Tests/StandaloneChecks.swift -framework IOKit -framework SystemConfiguration -o .build/MacPulseChecks
.build/MacPulseChecks
