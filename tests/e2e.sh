#!/usr/bin/env bash
# End-to-end tests: run the program on the fixtures and compare its output
# with the golden files in tests/fixtures/expected byte for byte, and its
# error messages and exit statuses with the expected ones.
#
# usage: tests/e2e.sh COMMAND
#   COMMAND is the built binary (build/imgfx) or, for `make parity`, the
#   interpreter: "loup run source/main.lphc --". Both must pass unchanged.

set -u
read -r -a CMD <<< "$1"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FIX=tests/fixtures
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() {
    fail=$((fail + 1))
    echo "FAIL: $1"
    sed 's/^/    stderr: /' "$TMP/err" | head -5
}

# run ARGS...: runs COMMAND with standard input from $IN (default
# /dev/null); sets $status.
run() {
    "${CMD[@]}" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    status=$?
}

# golden NAME GOLDEN [ARGS...]: status 0 and standard output identical to
# tests/fixtures/expected/GOLDEN.
golden() {
    local name=$1 want=$FIX/expected/$2
    shift 2
    run "$@"
    if [ "$status" -eq 0 ] && cmp -s "$want" "$TMP/out"; then ok; else bad "$name (exit $status)"; fi
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]: exact standard error and
# no standard output.
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    if [ "$status" -eq "$want_status" ] && cmp -s "$TMP/want" "$TMP/err" && [ ! -s "$TMP/out" ]; then
        ok
    else
        bad "$name (exit $status, expected $want_status)"
        diff "$TMP/want" "$TMP/err" | sed 's/^/    /' | head -6
    fi
}

# --- every filter, against golden files ------------------------------------
golden "copy P6"             rgb.copy.ppm          $FIX/rgb.ppm
golden "grayscale"           rgb.grayscale.pgm     $FIX/rgb.ppm grayscale
golden "invert"              rgb.invert.ppm        $FIX/rgb.ppm invert
golden "brightness"          rgb.brightness.ppm    $FIX/rgb.ppm brightness=60
golden "contrast"            rgb.contrast.ppm      $FIX/rgb.ppm contrast=1.5
golden "box blur"            rgb.blur2.ppm         $FIX/rgb.ppm blur=2
golden "gaussian"            rgb.gaussian2.ppm     $FIX/rgb.ppm gaussian=2
golden "sobel"               rgb.sobel.pgm         $FIX/rgb.ppm sobel
golden "nearest"             rgb.nearest.ppm       $FIX/rgb.ppm nearest=7x5
golden "bilinear"            rgb.bilinear.ppm      $FIX/rgb.ppm bilinear=33x25
golden "crop"                rgb.crop.ppm          $FIX/rgb.ppm crop=3,2,8,6
golden "flip h"              rgb.fliph.ppm         $FIX/rgb.ppm flip=h
golden "flip v"              rgb.flipv.ppm         $FIX/rgb.ppm flip=v
golden "chain"               rgb.chain.pgm         $FIX/rgb.ppm gaussian sobel invert
golden "P2 output, wrapped"  rgb.p2.pgm            -f P2 $FIX/rgb.ppm contrast=0.5
golden "P5 blur"             gray.blur.pgm         $FIX/gray.pgm blur
golden "gray to P3"          gray.p3.ppm           -f P3 $FIX/gray.pgm
golden "P3 in, P3 out"       plain.invert.ppm      $FIX/plain.ppm invert
golden "P3 to P6 bilinear"   plain.bilinear.ppm    --format=P6 $FIX/plain.ppm bilinear=9x7
golden "P2 maxval 15"        small.copy.pgm        $FIX/small.pgm
golden "P2 to P6 nearest"    small.nearest.ppm     -f p6 $FIX/small.pgm nearest=10x8

# --- input and output --------------------------------------------------------
IN=$FIX/rgb.ppm golden "standard input"  rgb.invert.ppm  - invert
run $FIX/rgb.ppm -o "$TMP/out.ppm" invert
[ "$status" -eq 0 ] && [ ! -s "$TMP/out" ] && cmp -s "$TMP/out.ppm" $FIX/expected/rgb.invert.ppm && ok || bad "-o FILE"
golden "-o -"  rgb.invert.ppm  $FIX/rgb.ppm -o - invert
golden "options after filters"  rgb.p2.pgm  $FIX/rgb.ppm contrast=0.5 --format P2

# --- bad input (status 1) ----------------------------------------------------
printf 'GIF89a' > "$TMP/x.gif"
printf 'P6\n4 4\n255\nabc' > "$TMP/short.ppm"
printf 'P5\n2 2\n65535\n' > "$TMP/deep.pgm"
printf 'P2\n2 1\n9\n3 10\n' > "$TMP/over.pgm"
check_err "missing file"    1 "imgfx: $TMP/none.ppm: cannot read: no such file
"  "$TMP/none.ppm"
check_err "bad magic"       1 "imgfx: $TMP/x.gif: not a PGM or PPM image (bad magic number)
"  "$TMP/x.gif"
check_err "truncated"       1 "imgfx: $TMP/short.ppm: truncated raster: expected 48 bytes, found 3
"  "$TMP/short.ppm"
check_err "16-bit"          1 "imgfx: $TMP/deep.pgm: 16-bit samples are not supported (maximum value 65535)
"  "$TMP/deep.pgm"
check_err "sample too big"  1 "imgfx: $TMP/over.pgm: sample 10 is above the maximum value 9
"  "$TMP/over.pgm"
check_err "crop outside"    1 "imgfx: $FIX/rgb.ppm: crop 10,10,8,8 is outside the 16x12 image
"  $FIX/rgb.ppm crop=10,10,8,8
check_err "no output dir"   1 "imgfx: $TMP/no/out.ppm: cannot write: no such directory
"  $FIX/rgb.ppm -o "$TMP/no/out.ppm"

# --- usage errors (status 2), found before the input is read ------------------
try=$'Try \'imgfx --help\' for more information.\n'
check_err "no input"        2 $'imgfx: no input file (use \'-\' for standard input)\n'"$try"
check_err "unknown filter"  2 $'imgfx: unknown filter \'sharpen\'\n'"$try"                  "$TMP/none.ppm" sharpen
check_err "bad radius"      2 $'imgfx: \'blur\' needs a radius from 1 to 25, not \'0\'\n'"$try"  "$TMP/none.ppm" blur=0
check_err "bad size"        2 $'imgfx: \'bilinear\' needs a size WxH (1 to 16384 each), not \'10\'\n'"$try"  "$TMP/none.ppm" bilinear=10
check_err "bad contrast"    2 $'imgfx: \'contrast\' needs a factor from 0 to 10 (up to 3 decimals), not \'x\'\n'"$try"  "$TMP/none.ppm" contrast=x
check_err "unknown option"  2 $'imgfx: unrecognized option \'--bogus\'\n'"$try"              "$TMP/none.ppm" --bogus
check_err "unknown format"  2 $'imgfx: unknown format \'P4\' (P2, P3, P5 or P6)\n'"$try"     "$TMP/none.ppm" -f P4
check_err "missing value"   2 $'imgfx: option \'-o\' requires an argument\n'"$try"           "$TMP/none.ppm" -o

# --- help and version ----------------------------------------------------------
run --version
[ "$status" -eq 0 ] && [ "$(cat "$TMP/out")" = "imgfx (loup-cmd-imgfx) 0.1.0" ] && ok || bad "--version"
run --help
[ "$status" -eq 0 ] && [ "$(head -1 "$TMP/out")" = "usage: imgfx [OPTIONS] INPUT [FILTER...]" ] && ok || bad "--help"

echo "e2e ($1): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
