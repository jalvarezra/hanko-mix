#!/usr/bin/env bash
# Regenerates Sources/HankoMix/Resources/autoeq.json from a pinned AutoEq commit.
# AutoEq (https://github.com/jaakkopasanen/AutoEq) is MIT licensed; see THIRD_PARTY_NOTICES.md.
set -euo pipefail
AUTOEQ_COMMIT="7ae0f56d53074872b028649617a22bbb4232feb7"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKOUT="$ROOT/build/AutoEq"

if [ ! -d "$CHECKOUT/.git" ]; then
  git clone --filter=blob:none --no-checkout https://github.com/jaakkopasanen/AutoEq.git "$CHECKOUT"
fi
cd "$CHECKOUT"
git fetch --quiet --depth 1 origin "$AUTOEQ_COMMIT" || true
git sparse-checkout init --no-cone
git sparse-checkout set --no-cone '/LICENSE' '/results/**/*ParametricEQ.txt'
git checkout --quiet "$AUTOEQ_COMMIT"

cd "$ROOT"
swift run -c release autoeq-index "$CHECKOUT/results" "$ROOT/Sources/HankoMix/Resources/autoeq.json"
