# Build, check and test commands for this host.native Loup application.
#
# On Linux x86-64 `loup` is the self-hosted driver and `loup-bootstrap` is
# Stage0. `check`, the native build and the tests use Stage0 (the tests are
# host.native files, which Stage0 builds and runs as native binaries).
# `run`, `parity` and `bench` interpret the same source to show that both
# lanes agree and how far apart they are. The interpreter is Stage0's
# (`loup-bootstrap run`, which is what `loup run` is on macOS, Windows and
# Linux arm64): the self-hosted `loup run` of Loup 1.26.0 silently drops a
# `writeBytes` of 26,210 bytes or more, which most images are.

APP            ?= imgfx
LOUP_BOOTSTRAP ?= loup-bootstrap
BUILD_DIR      ?= build
BIN            := $(BUILD_DIR)/$(APP)
SOURCES        := package.lppkg $(shell find source -name '*.lphc')
ARGS           ?=
TEST_ARGS      ?=
INTERP         ?= $(LOUP_BOOTSTRAP) run source/main.lphc --
BENCH_SIZE     ?= 512
BENCH_FILTERS  ?= gaussian=2 sobel bilinear=384x384

.PHONY: all run check test build e2e parity bench ci clean

all: build

# Run from source with the interpreter, e.g.
# `make run ARGS="tests/fixtures/rgb.ppm -o out.ppm invert"`.
run:
	$(INTERP) $(ARGS)

# Type-check source/main.lphc and every module it imports.
check:
	$(LOUP_BOOTSTRAP) check --no-color

# Each test_* function becomes its own native binary (about a second each).
# The generated test package lives in a temporary directory, so LOUPPATH
# must be absolute: source/ for the program's modules, tests/ for the
# shared helpers. Narrow the run with TEST_ARGS, e.g.
# `make test TEST_ARGS="--filter blur"`.
test:
	@mkdir -p .temp
	LOUPPATH=$(CURDIR)/source:$(CURDIR)/tests$${LOUPPATH:+:$$LOUPPATH} $(LOUP_BOOTSTRAP) test --native --no-color $(TEST_ARGS) > .temp/test.log 2>&1; \
	status=$$?; cat .temp/test.log; exit $$status
	@# A test file that does not compile is skipped silently ("found 0 tests"),
	@# so a full run must account for every test_ function.
	@if [ -z "$(TEST_ARGS)" ]; then \
	    want=$$(cat tests/*_test.lphc | grep -c '^func test_'); \
	    got=$$(sed -n 's/^Tests: \([0-9]*\) total.*/\1/p' .temp/test.log); \
	    if [ "$$want" != "$$got" ]; then \
	        echo "make test: ran $$got of $$want tests; a test file did not compile (find it with: LOUPPATH=source:tests loup-bootstrap run tests/FILE)"; \
	        exit 1; \
	    fi; \
	fi

# Native executable (needs clang).
build: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(LOUP_BOOTSTRAP) build --target native -o $@

# End-to-end tests: run the built binary on the fixtures and compare its
# output with the golden files byte for byte.
e2e: $(BIN)
	bash tests/e2e.sh $(BIN)

# The same end-to-end tests through the interpreter: it must produce the
# same bytes as the native binary.
parity:
	bash tests/e2e.sh "$(INTERP)"

# Time one filter chain on a generated BENCH_SIZE x BENCH_SIZE image,
# interpreted and as a native binary (not part of ci).
bench: $(BIN)
	bash tests/bench.sh $(BIN) "$(INTERP)" $(BENCH_SIZE) $(BENCH_FILTERS)

# Everything CI runs, ending with a smoke test of the built binary.
ci: check test build e2e parity
	$(BIN) --version

clean:
	rm -rf $(BUILD_DIR) .temp .loup-cache
