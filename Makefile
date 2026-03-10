.PHONY: build test clean run-demo

build:
	v -o vector-v src/

test:
	v test src/event/
	v test src/conf/
	v test src/transforms/

clean:
	rm -f vector-v

run-demo:
	echo "hello world" | ./vector-v -c examples/stdin_to_stdout.toml
