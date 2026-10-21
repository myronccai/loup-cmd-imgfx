# Design: imgfx

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses the options
and every filter specification before touching the input (so a typo is a
usage error, not a half-done job), reads the image, applies the filters left
to right, and writes the result. Decoding, filters and encoding are pure
functions from values to values (`Image` in, `Image` or bytes out), so the
tests need no files except the golden fixtures.

All sources are `@mode(host.native)` `.lphc` files. Nothing here needs
`asm` or `unique class`; the point of `host.native` is the build: the same
code is interpreted (`loup-bootstrap run`) and compiled
(`loup-bootstrap build --target native`), and the filters are exactly the
kind of tight integer loops where that matters.

## Modules

| Module | Contents |
|---|---|
| `source/main.lphc` | entry point: `run(runtime.args())` |
| `source/appinfo.lphc` | name, version, summary, exit statuses |
| `source/cli/args.lphc` | `Options`, `parse_args` |
| `source/cli/usage.lphc` | `usage()`, `version_line()` |
| `source/cli/app.lphc` | `run()`: parse, help/version, run, map errors to statuses |
| `source/image/image.lphc` | `Image` (width, height, channels, samples), `to_gray`, `to_rgb`, `clamp_sample`, `round_div` |
| `source/image/pnm.lphc` | `decode_pnm(bytes)` (header read with an `io.streams.ByteReader`), `encode_pnm(image, format)` (byte values as `list[int]`), `output_format` |
| `source/filters/spec.lphc` | `Filter`, `parse_filter`, `parse_decimal_milli`, `parse_size` |
| `source/filters/point.lphc` | `grayscale`, `invert`, `brightness`, `contrast`, `lut(f)` (256-entry table of a lambda) |
| `source/filters/convolve.lphc` | `box_blur`, `gaussian_blur`, `sobel`, `binomial_row`, `isqrt` |
| `source/filters/geometry.lphc` | `resize_nearest`, `resize_bilinear`, `crop`, `flip` |
| `source/filters/chain.lphc` | `apply_filter`, `apply_all` (one profiler span per filter) |
| `source/commands/imgfx.lphc` | `process` (decode, filters, encode as `debug.profiler` spans), `render_profile`, `run_imgfx`: read, filter, write |

### Images

`Image` holds `width`, `height`, `channels` (1 or 3) and `samples:
list[int]`, row-major with interleaved channels, every sample 0..255.

### Integer arithmetic only

- Box blur: a horizontal pass of window sums, a vertical pass of sums of
  sums, one rounded division by (2R+1)².
- Gaussian: the same with binomial weights C(2R, k); the divisor is
  `4 ** (2 * R)` = 16^R.
- Contrast: the factor is parsed to thousandths; `(v − 128) × F / 1000` is
  rounded half away from zero.
- Bilinear: source coordinates in 1/256 pixel,
  `fx = ((2x + 1) × sw × 256) / (2 × dw) − 128`, clamped to the image;
  weights are the low 8 bits.
- Sobel: `isqrt` is `floor(sqrt(n))` with `core.math`. The only float in the
  program, and exact: n ≤ 2 × 1020², a double holds it exactly, `sqrt` is
  correctly rounded, and just below k² the true root is about 1/(2k) under
  k, far more than the rounding error (a unit test checks every n).

So there is no rounding difference between the interpreter and LLVM, and
the golden files hold for both lanes.

## Differences from other tools

There is no original command; netpbm's `pnmconvol`, `pamscale`, `pamcut`,
`pamflip` and ImageMagick do the same jobs with more options.

- Only 8-bit samples (maximum value ≤ 255); output is always 255.
- No PAM (P7) or PBM (P1/P4) input.
- Gaussian blur uses binomial weights instead of `exp`.

## Error handling

Usage errors (status 2) are found before the input is read. A bad image, an
unreadable input, a crop outside the image or an unwritable output raise an
`ImageError` and give `imgfx: message` with status 1. The input's existence
and the output's directory are checked first, because a failed read or
write ends a native program outright in Loup 1.26.0.

## Testing

All unit tests are `@mode(host.native)`, built and run natively by
`loup-bootstrap test --native`.

- `tests/pnm_test.lphc`: headers, comments, scaling, truncation, every
  format, plain-text line length.
- `tests/spec_test.lphc`: filter specifications and their limits.
- `tests/point_test.lphc`, `tests/convolve_test.lphc`,
  `tests/geometry_test.lphc`: each filter on tiny hand-checked images.
- `tests/args_test.lphc`, `tests/app_test.lphc`: options and statuses.
- `tests/e2e.sh`: the binary against the golden files in
  `tests/fixtures/` (inputs and `expected/` outputs), byte for byte.
- `make parity` runs the same `tests/e2e.sh` through the interpreter.
- `make bench` (not in CI) times a filter chain on a 512×512 image in both
  lanes.
