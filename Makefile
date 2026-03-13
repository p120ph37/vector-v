.PHONY: build thirdparty test test-vrl clean run-demo bench bench-v bench-rust

# Build thirdparty static libraries first, then compile
build: thirdparty
	v -enable-globals -o vector-v src/

thirdparty:
	@sh thirdparty/xxhash/build.sh

test: thirdparty
	v -enable-globals test src/event/
	v -enable-globals test src/conf/
	v -enable-globals test src/transforms/

test-vrl: thirdparty
	v -enable-globals test src/vrl/

clean:
	rm -f vector-v
	rm -f thirdparty/xxhash/libxxhash.a thirdparty/xxhash/xxhash_wrapper.o

run-demo:
	echo "hello world" | ./vector-v -c examples/stdin_to_stdout.toml

bench-v: thirdparty
	v -prod -cc clang -path "src|@vlib|@vmodules" -o bench/v-vrl/bench bench/v-vrl/bench.v
	bench/v-vrl/bench

bench-rust:
	cd bench/rust-vrl && cargo build --release 2>/dev/null
	bench/rust-vrl/target/release/vrl-bench

bench: bench-v bench-rust
