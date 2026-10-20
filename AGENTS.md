# AGENTS.md

This repository is `imgfx`, an image-filter tool for PGM and PPM images
written in the Loup programming language, as part of the loup-cmd series of
example applications. It is a `host.native` project: every source file is
`.lphc`, the program ships as a native binary, and the same source also runs
under the interpreter, which `make parity` and `make bench` use to show that
both lanes agree and how far apart they are in speed.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # Loup manifest: name, version, toolchain, [build] entry, [test] pattern
├── Makefile                     # run, check, test, build, e2e, parity, bench, ci, clean
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main.lphc                # entry point: func main() calls run(runtime.args())
│   ├── appinfo.lphc             # APP_NAME, APP_VERSION, APP_SUMMARY, exit statuses
│   ├── cli/
│   │   ├── args.lphc            # struct Options, parse_args(), parse_format()
│   │   ├── usage.lphc           # usage(), version_line()
│   │   └── app.lphc             # run(): parse, --help/--version, run_imgfx, exit status
│   ├── image/
│   │   ├── image.lphc           # struct Image, ImageError, to_gray(), to_rgb(), clamp(), round_div()
│   │   └── pnm.lphc             # decode_pnm(), encode_pnm(), output_format()
│   ├── filters/
│   │   ├── spec.lphc            # struct Filter, parse_filter() and number parsers
│   │   ├── point.lphc           # grayscale(), invert(), brightness(), contrast()
│   │   ├── convolve.lphc        # box_blur(), gaussian_blur(), sobel(), isqrt()
│   │   ├── geometry.lphc        # resize_nearest(), resize_bilinear(), crop(), flip()
│   │   └── chain.lphc           # apply_filter(), apply_all()
│   └── commands/
│       └── imgfx.lphc           # process(), run_imgfx(): read, filter, write
├── tests/
│   ├── *_test.lphc              # native unit tests: func test_*(): void
│   ├── helpers.lphc             # expect_text(), image(), describe(), ascii()
│   ├── fixtures/                # sample images; expected/ holds the golden outputs
│   ├── e2e.sh                   # end-to-end tests: build/imgfx or the interpreter
│   └── bench.sh                 # interpreted vs native timing
├── specs/imgfx/                 # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs Loup and runs `make ci`
└── build/                       # build output (git-ignored)
```

## Build, run and test

Prerequisites: Linux x86-64, Loup 1.26.0 (`loup` and `loup-bootstrap` on
`PATH`), `make`, and `clang` 17 or later.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run from source | `make run ARGS="tests/fixtures/rgb.ppm -o out.ppm sobel"` | `loup-bootstrap run source/main.lphc -- ARGS` |
| Type-check | `make check` | checks `source/main.lphc` and every module it imports; tests are not checked |
| Run all tests | `make test` | every `tests/*_test.lphc`, each test built as a native binary (about 1 s each) |
| Run matching tests | `make test TEST_ARGS="--filter blur"` | tests whose name contains `blur` |
| Run one test file | `make test TEST_ARGS="--file tests/pnm_test.lphc"` | |
| Build | `make build` | native binary at `build/imgfx` |
| End-to-end tests | `make e2e` | runs `tests/e2e.sh build/imgfx` against the golden files |
| Interpreter parity | `make parity` | the same `tests/e2e.sh` through `loup-bootstrap run` |
| Benchmark | `make bench` | 512×512 by default; `BENCH_SIZE=256 BENCH_FILTERS="blur=3"` to change; not in CI |
| Everything CI runs | `make ci` | check, test, build, e2e, parity, then `build/imgfx --version` |
| Clean | `make clean` | removes `build/`, `.temp/` and `.loup-cache/` |

Run `make ci` before reporting a change as done.

Every step uses `loup-bootstrap` (Stage0). The self-hosted `loup` refuses
`check`; Stage0 runs `host.native` test files through the native AOT
pipeline in a temporary package outside the repository (hence the absolute
`LOUPPATH=$(CURDIR)/source:$(CURDIR)/tests`, and relative file names in tests
land in that temporary directory); and the self-hosted `loup run` silently
drops a `writeBytes` of 26,210 bytes or more, so the interpreted lane is
`loup-bootstrap run`.

## Making a change

1. Update the spec in `specs/imgfx/` (see [specs/README.md](specs/README.md)).
2. Change the code under `source/`.
3. Add or update unit tests in `tests/`, and golden files in
   `tests/fixtures/expected/` with cases in `tests/e2e.sh`. Check a new
   golden file by hand (small plain-text output is readable) before
   committing it: the binary must not be its own oracle.
4. Run `make ci`.
5. Tick the finished tasks in `specs/imgfx/tasks.md`.

Keep filters pure and integer-only (no `float`): that is what makes the two
lanes byte-identical. Only `run_imgfx` reads and writes files.

## Conventions

- Every source file is `@mode(host.native)` with the `.lphc` extension. Only
  `source/main.lphc` has a `main()`.
- Modules import each other by path from `source/`:
  `from filters.spec import (Filter);`. Tests import them the same way. Do not
  use relative imports.
- Struct fields read from another module must be `pub`.
- Loup 1.26.0 pitfalls this code works around:
  - `match` on a `string` always takes the `_` arm in Stage0 native code: use
    `if (s == "x") ... else if` chains (see `apply_filter`).
  - A failed `readBytes` ends a native program outright (no `catch`), so
    `run_imgfx` checks `exists` first.
  - `.len()` or indexing on a let-bound `bytes` returned from a function
    crashes natively: the encoder returns `list[int]`, and `bytesFromInts`
    is called at the write.
  - The self-hosted `loup run` leaves escapes such as `\n` undecoded inside
    `i"..."` strings: concatenate plain strings instead.
  - `expectEq` on two equal strings fails in native tests: use
    `expect_text(actual, expected, context)` from `tests/helpers.lphc`.
  - A test file that does not compile is skipped silently. A full
    `make test` therefore fails unless it ran every `test_` function; find
    the broken file with `LOUPPATH=source:tests loup-bootstrap run tests/FILE`.
- Keep `APP_VERSION` in `source/appinfo.lphc` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
