#!/bin/bash
# Compiles the pure-logic sources together with the tests and runs them.
# (SwiftPM from Command Line Tools can't link Package.swift on this setup.)
set -e

cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/TickTests"
swiftc Sources/Tick/DailyReminder.swift Sources/Tick/ReminderParser.swift Sources/Tick/GlobalHotKey.swift Tests/*.swift \
    -o "$OUT" -sdk "$(xcrun --show-sdk-path)" -parse-as-library
"$OUT"
