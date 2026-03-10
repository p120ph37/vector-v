.PHONY: build build-jit test test-vrl test-jit clean run-demo bench bench-v bench-jit bench-rust

build:
	v -o vector-v src/

build-jit:
	v -d jit -o vector-v src/

test:
	v test src/event/
	v test src/conf/
	v test src/transforms/

test-vrl:
	v test src/vrl/

test-jit:
	v -d jit test src/vrl/

clean:
	rm -f vector-v

run-demo:
	echo "hello world" | ./vector-v -c examples/stdin_to_stdout.toml

bench-v:
	v -prod -cc clang -path "src|@vlib|@vmodules" -o bench/v-vrl/bench bench/v-vrl/bench.v
	bench/v-vrl/bench

bench-jit:
	v -prod -cc clang -d jit -path "src|@vlib|@vmodules" -o bench/v-vrl-jit/bench bench/v-vrl-jit/bench.v
	bench/v-vrl-jit/bench

bench-rust:
	cd bench/rust-vrl && cargo build --release 2>/dev/null
	bench/rust-vrl/target/release/vrl-bench

bench: bench-v bench-jit bench-rust
