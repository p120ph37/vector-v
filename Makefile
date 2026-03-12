.PHONY: build test test-vrl clean run-demo bench bench-v bench-rust

build:
	v -enable-globals -o vector-v src/

test:
	v -enable-globals test src/event/
	v -enable-globals test src/conf/
	v -enable-globals test src/transforms/

test-vrl:
	v -enable-globals test src/vrl/

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
