#!/bin/bash
# Compiles the pure-logic sources together with the tests and runs them.
# (SwiftPM from Command Line Tools can't link Package.swift on this setup.)
set -e

cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/ChivvyTests"
swiftc Sources/Chivvy/DailyReminder.swift Sources/Chivvy/ReminderParser.swift Sources/Chivvy/GlobalHotKey.swift \
    Sources/Chivvy/Localization.swift Sources/Chivvy/TimerPreset.swift Sources/Chivvy/AlertText.swift \
    Sources/Chivvy/MainSection.swift Tests/*.swift \
    -o "$OUT" -sdk "$(xcrun --show-sdk-path)" -parse-as-library
"$OUT"
