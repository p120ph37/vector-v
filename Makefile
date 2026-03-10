.PHONY: build build-jit test test-vrl test-jit clean run-demo

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
