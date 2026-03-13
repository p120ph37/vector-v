.PHONY: build test test-vrl test-all clean run-demo bench bench-v bench-rust \
       coverage coverage-json coverage-verbose \
       coverage-runtime coverage-clean

build:
	v -enable-globals -o vector-v src/

test:
	v -enable-globals test src/event/
	v -enable-globals test src/conf/
	v -enable-globals test src/transforms/

test-vrl:
	v -enable-globals test src/vrl/

test-all:
	v -enable-globals test src/event/
	v -enable-globals test src/conf/
	v -enable-globals test src/transforms/
	v -enable-globals test src/sinks/
	v -enable-globals test src/sources/
	v -enable-globals test src/topology/
	v -enable-globals test src/api/
	v -enable-globals test src/cliargs/
	v -enable-globals test src/vrl/

coverage:
	@python3 scripts/coverage.py --src src

coverage-json:
	@python3 scripts/coverage.py --src src --json

coverage-verbose:
	@python3 scripts/coverage.py --src src --verbose

coverage-runtime:
	@./scripts/runtime_coverage.sh

coverage-clean:
	rm -rf .coverage/

clean:
	rm -f vector-v

run-demo:
	echo "hello world" | ./vector-v -c examples/stdin_to_stdout.toml

bench-v:
	v -prod -cc clang -path "src|@vlib|@vmodules" -o bench/v-vrl/bench bench/v-vrl/bench.v
	bench/v-vrl/bench

bench-rust:
	cd bench/rust-vrl && cargo build --release 2>/dev/null
	bench/rust-vrl/target/release/vrl-bench

bench: bench-v bench-rust
