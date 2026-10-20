#!/usr/bin/env bash
# Times one filter chain under the interpreter and as a native binary, on a
# generated SIZE x SIZE noise image, and checks that both produce the same
# bytes. Not part of `make ci`: the interpreter run takes a while.
#
# usage: tests/bench.sh BINARY "INTERPRETER COMMAND" SIZE FILTER...

set -u
BIN=$1
read -r -a INTERP <<< "$2"
SIZE=$3
shift 3
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

{ printf 'P6\n%d %d\n255\n' "$SIZE" "$SIZE"; head -c $((SIZE * SIZE * 3)) /dev/urandom; } > "$TMP/in.ppm"

# seconds ARGS...: runs ARGS, prints the wall-clock time in seconds.
seconds() {
    local start end
    start=$(date +%s%N)
    "$@" > /dev/null || { echo "bench: '$*' failed" >&2; exit 1; }
    end=$(date +%s%N)
    awk -v ns=$((end - start)) 'BEGIN { printf "%.3f", ns / 1e9 }'
}

echo "image:   ${SIZE}x${SIZE} RGB (random noise)"
echo "filters: $*"
native=$(seconds "$BIN" "$TMP/in.ppm" -o "$TMP/native.ppm" "$@")
interp=$(seconds "${INTERP[@]}" "$TMP/in.ppm" -o "$TMP/interp.ppm" "$@")
if cmp -s "$TMP/native.ppm" "$TMP/interp.ppm"; then same="identical"; else same="DIFFERENT"; fi
printf '%-34s %8s s\n' "native ($BIN)" "$native"
printf '%-34s %8s s\n' "interpreted (${INTERP[*]:0:2})" "$interp"
awk -v n="$native" -v i="$interp" 'BEGIN { if (n > 0) printf "speed-up: %.0fx\n", i / n }'
echo "outputs: $same"
[ "$same" = "identical" ]
