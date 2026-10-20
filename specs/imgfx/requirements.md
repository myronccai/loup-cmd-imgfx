# Requirements: imgfx

## Introduction

`imgfx` applies image filters to Netpbm images (PGM and PPM): grayscale,
invert, brightness and contrast, box and Gaussian blur, Sobel edges, nearest
and bilinear resize, crop and flip, chained in one command. It is the third
host-compiled (`host.native`) project in the loup-cmd series and the one
about speed: the same source runs interpreted and as a native binary,
gives byte-identical output on both, and `make bench` shows the difference
in time.

## Requirements

### Requirement 1: Reading and writing images

**User Story:** As a user, I want to read and write the simple Netpbm
formats so that I can use the tool with other image software.

#### Acceptance Criteria

1. THE program SHALL read P2 and P5 (PGM) and P3 and P6 (PPM) images with a
   maximum value from 1 to 255, including `#` comments in the header.
2. WHEN the maximum value is below 255, THE program SHALL scale the samples to
   0..255; output always has maximum value 255.
3. WHEN the output format is not given, THE program SHALL keep the input's
   encoding (plain text for P2/P3, binary for P5/P6) and pick PGM or PPM from
   the result's channels; `--format P2|P3|P5|P6` SHALL force a format,
   converting gray to color (copying the channel) or color to gray (luma).
4. THE program SHALL read the input from FILE or, for `-`, standard input,
   and write to `-o FILE` or, without it, standard output.
5. WHEN the input is not a valid image (bad magic, bad header, maximum value
   above 255, too few samples), THE program SHALL report
   `imgfx: FILE: MESSAGE` and exit with status 1.
6. Plain-text output SHALL keep lines to 70 characters or fewer.

### Requirement 2: Filters

**User Story:** As a user, I want common filters, chained left to right.

#### Acceptance Criteria

1. `grayscale` SHALL convert to one channel with
   `Y = (77 R + 150 G + 29 B + 128) >> 8`.
2. `invert` SHALL replace each sample v with 255 − v.
3. `brightness=N` (−255..255) SHALL add N and clamp to 0..255.
4. `contrast=F` (0..10, up to three decimals) SHALL map v to
   `128 + (v − 128) × F`, rounded half away from zero and clamped.
5. `blur=R` (1..25, default 1) SHALL average the (2R+1)×(2R+1) window,
   rounding to nearest, with edge pixels repeated beyond the border.
6. `gaussian=R` (1..8, default 1) SHALL convolve with the separable binomial
   kernel of width 2R+1 (rows of Pascal's triangle), rounding to nearest, with
   edges repeated.
7. `sobel` SHALL convert to grayscale and output
   `min(255, floor(sqrt(Gx² + Gy²)))` of the 3×3 Sobel kernels, edges
   repeated.
8. `nearest=WxH` and `bilinear=WxH` (1..16384 each) SHALL resize, sampling at
   pixel centres; bilinear SHALL use 8-bit fixed-point weights.
9. `crop=X,Y,W,H` SHALL cut the rectangle, which must lie inside the image.
10. `flip=h` and `flip=v` SHALL mirror horizontally and vertically.
11. All filters SHALL use integer arithmetic only, so the interpreter and the
    native binary produce identical bytes.

### Requirement 3: Command line

**User Story:** As a shell user, I want the usual conventions.

#### Acceptance Criteria

1. THE grammar SHALL be `imgfx [OPTIONS] INPUT [FILTER...]`; with no filter
   the image is converted (or copied) to the output format.
2. WHEN `-h` / `--help` is given, THE program SHALL print the help text; `-V`
   / `--version` SHALL print `imgfx (loup-cmd-imgfx) 0.1.0`; both exit 0.
3. WHEN the input is missing, an option or filter is unknown, or a filter
   argument is invalid, THE program SHALL print `imgfx: MESSAGE` and
   `Try 'imgfx --help' for more information.` on standard error and exit
   with status 2, before reading the input.
4. Exit statuses: 0 success, 1 bad or unreadable input or unwritable output,
   2 usage error.

### Requirement 4: Speed

**User Story:** As a reader of the example, I want to see what compiling
buys.

#### Acceptance Criteria

1. `make bench` SHALL generate a larger image, run the same filter chain
   interpreted (`loup-bootstrap run`) and with the native binary, check that
   the outputs are identical, and print both times. It SHALL NOT be part of
   `make ci`.
2. `make parity` SHALL run the end-to-end tests through the interpreter as
   well, and be part of `make ci`.
3. The interpreter SHALL be Stage0's `loup-bootstrap run` (what `loup run`
   is on macOS, Windows and Linux arm64): the self-hosted `loup run` of Loup
   1.26.0 on Linux x86-64 silently drops a `writeBytes` of 26,210 bytes or
   more.
