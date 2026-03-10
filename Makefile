.PHONY: build test test-vrl clean run-demo bench bench-v bench-rust

build:
	v -o vector-v src/

test:
	v test src/event/
	v test src/conf/
	v test src/transforms/

test-vrl:
	v test src/vrl/

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
