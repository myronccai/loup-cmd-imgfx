# loup-cmd-imgfx

Image filters for Netpbm images (PGM and PPM: P2, P3, P5, P6) in
[Loup](https://code-craft.ai/references/loup): grayscale, invert, brightness
and contrast, box and Gaussian blur, Sobel edges, nearest and bilinear
resize, crop and flip, chained left to right in one command.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.native` (host-compiled) project.

## What this example shows

- **Why you compile.** Image filters are tight integer loops over every
  sample, and the same `.lphc` source runs both interpreted and as a native
  binary. `make bench` runs one filter chain both ways on a 512×512 image:

  ```text
  $ make bench
  bash tests/bench.sh build/imgfx "loup-bootstrap run source/main.lphc --" 512 gaussian=2 sobel bilinear=384x384
  image:   512x512 RGB (random noise)
  filters: gaussian=2 sobel bilinear=384x384
  native (build/imgfx)                  0.165 s
  interpreted (loup-bootstrap run)     29.346 s
  speed-up: 178x
  outputs: identical
  ```

  (On a Ryzen 9 7940HS with other jobs running; the ratio is what matters.
  The interpreter is Stage0's, for the reason under Limits.)

- **One source, two lanes, identical bytes.** Every filter uses integer
  arithmetic (fixed-point bilinear weights, binomial Gaussian weights); the
  one floating-point step, Sobel's square root, is a correctly rounded
  `core.math.sqrt` floored to an integer, which is exact for every value
  Sobel can produce (a unit test checks all of them). So the interpreter
  and LLVM cannot round differently. `make ci` runs the end-to-end tests against the golden
  files twice: on the binary (`make e2e`) and through the interpreter
  (`make parity`).
- **Pure functions.** Decoding, every filter and encoding take values and
  return values (`Image`, a list of byte values), so the unit tests need no
  files; the golden outputs were cross-checked against an independent
  implementation of the same formulas.

- **Where the time goes.** `--profile` times decoding, each filter and
  encoding as `debug.profiler` spans and reports them on standard error;
  the unit tests drive the same code with `Profiler.manual()`, whose clock
  moves only when told to, to check exact numbers.

`host.native` is what lets a program be shipped as a native binary at all;
this project uses no `asm` or `unique class` (see loup-cmd-cpuid and
loup-cmd-kvstore for those): its point is the build.

## Requirements

- Linux x86-64.
- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, and `clang` 17 or later for the native build.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make build                    # native binary: build/imgfx
make ci                       # check, native unit tests, build, e2e in both lanes
make bench                    # interpreted vs native timing (not part of ci)
make run ARGS="tests/fixtures/rgb.ppm -o out.ppm sobel"   # interpreted run
```

```text
$ build/imgfx tests/fixtures/rgb.ppm -o edges.pgm gaussian=2 sobel
$ build/imgfx tests/fixtures/rgb.ppm -o big.ppm bilinear=160x120 contrast=1.2
$ build/imgfx tests/fixtures/gray.pgm invert flip=v > flipped.pgm
$ cat tests/fixtures/rgb.ppm | build/imgfx - grayscale -f P5 > gray.pgm
$ head -c 13 edges.pgm | od -c | head -1
0000000   P   5  \n   1   6       1   2  \n   2   5   5  \n
```

Plain-text formats make small results readable:

```text
$ build/imgfx tests/fixtures/rgb.ppm -f P2 grayscale nearest=8x4
P2
8 4
255
23 33 44 54 64 74 84 95
64 74 102 112 123 115 125 135
105 115 143 153 164 156 166 176
145 155 165 176 186 196 206 217
$ build/imgfx tests/fixtures/rgb.ppm crop=20,0,4,4
imgfx: tests/fixtures/rgb.ppm: crop 20,0,4,4 is outside the 16x12 image
$ build/imgfx tests/fixtures/rgb.ppm sharpen
imgfx: unknown filter 'sharpen'
Try 'imgfx --help' for more information.
```

`--profile` reports each step's time on standard error, so the image on
standard output or in `-o` is unchanged (here a 512×512 noise image):

```text
$ build/imgfx --profile noise.ppm -o n.pgm gaussian=2 sobel bilinear=384x384
imgfx: profile (milliseconds)
  decode            11.917
  1 gaussian        33.859
  2 sobel           24.519
  3 bilinear         5.786
  encode             1.858
  total             77.940
```

## Filters and options

```text
$ build/imgfx --help
usage: imgfx [OPTIONS] INPUT [FILTER...]

Apply image filters to PGM and PPM images (P2, P3, P5, P6).
Filters run left to right. INPUT '-' reads standard input.

Filters:
  grayscale             one channel: (77 R + 150 G + 29 B + 128) >> 8
  invert                255 - v
  brightness=N          add N (-255..255)
  contrast=F            128 + (v - 128) * F (0..10, e.g. 1.5)
  blur[=R]              mean of the (2R+1)x(2R+1) window (R 1..25, default 1)
  gaussian[=R]          binomial blur of width 2R+1 (R 1..8, default 1)
  sobel                 edge magnitude (grayscale)
  nearest=WxH           resize, nearest neighbour
  bilinear=WxH          resize, bilinear
  crop=X,Y,W,H          cut out a rectangle
  flip=h, flip=v        mirror left-right or top-bottom

Options:
  -o, --output FILE     write FILE instead of standard output
  -f, --format FMT      output format P2, P3, P5 or P6 (default: the
                        input's plain/binary encoding, gray or color)
      --profile         report the time of each step on standard error
  -h, --help            show this help and exit
  -V, --version         show the version and exit

Exit status: 0 success, 1 bad input or output, 2 usage error.
```

- Blurs and Sobel repeat the edge pixels beyond the border. The Gaussian
  uses the binomial weights of row 2R of Pascal's triangle (1 2 1,
  1 4 6 4 1, ...), a close approximation of σ = √(R/2).
- Resizes sample at pixel centres; bilinear uses 8-bit fixed-point weights.
- Without `-f`, the output keeps the input's encoding (plain text for
  P2/P3, binary for P5/P6) and is PGM or PPM by the result's channels
  (`grayscale` and `sobel` give one channel). With `-f`, gray is copied to
  three channels or color is reduced to luma.
- Every filter argument is checked before the input is read.

## Limits

- 8-bit samples only: a maximum value above 255 is refused; a lower one is
  scaled to 0..255, and output always uses 255.
- No PBM (P1/P4) or PAM (P7), no PNG or JPEG.
- The whole image is held in memory as a list of ints (up to 16384 pixels
  per side).
- Standard output is written by reopening `/dev/stdout`, so `>>` or a group
  redirection such as `{ echo x; imgfx ...; } > f` truncates the file; use
  `-o FILE`, a plain `>`, or a pipe (`imgfx in.ppm | cat >> all.ppm`).
  Loup 1.26.0 has no call that writes bytes to an open descriptor in both
  lanes: `writeBytes` opens the path with truncation, `appendText` cannot
  carry binary samples in the interpreter (strings are UTF-8 there), and the
  interpreter cannot call libc's `write` or `putchar`.
- The interpreted lane is Stage0's `loup-bootstrap run`: the self-hosted
  `loup run` of Loup 1.26.0 on Linux x86-64 silently drops a `writeBytes` of
  26,210 bytes or more, which almost every image is.

## Layout

```text
source/main.lphc              # entry point
source/appinfo.lphc           # name, version, exit statuses
source/cli/args.lphc          # options, input, filter list
source/cli/usage.lphc         # --help and --version text
source/cli/app.lphc           # run(): parse, dispatch, exit status
source/image/image.lphc       # Image, gray/RGB conversion, rounding helpers
source/image/pnm.lphc         # PGM/PPM decoding and encoding
source/filters/spec.lphc      # filter specifications and their limits
source/filters/point.lphc     # grayscale, invert, brightness, contrast
source/filters/convolve.lphc  # box blur, Gaussian, Sobel
source/filters/geometry.lphc  # nearest, bilinear, crop, flip
source/filters/chain.lphc     # apply the filters in order
source/commands/imgfx.lphc    # read, filter, write; the --profile report
tests/*_test.lphc             # native unit tests (make test)
tests/helpers.lphc            # shared test helpers
tests/fixtures/               # sample images; expected/ holds the golden outputs
tests/e2e.sh                  # end-to-end tests (make e2e, make parity)
tests/bench.sh                # make bench
specs/imgfx/                  # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
