use std::collections::BTreeMap;
use std::time::Instant;
use vrl::compiler::{compile, Context, TargetValue, TimeZone};
use vrl::compiler::state::RuntimeState;
use vrl::value;

fn run_benchmark(name: &str, source: &str, input: value::Value, iterations: u64) {
    // Compile once
    let fns = vrl::stdlib::all();
    let result = compile(source, &fns);
    let program = match result {
        Ok(res) => res.program,
        Err(e) => {
            eprintln!("Compilation error for '{}': {:?}", name, e);
            return;
        }
    };

    // Warm up
    for _ in 0..100 {
        let mut target = TargetValue {
            value: input.clone(),
            metadata: value::Value::Object(BTreeMap::new()),
            secrets: vrl::value::Secrets::default(),
        };
        let mut state = RuntimeState::default();
        let tz = TimeZone::default();
        let mut ctx = Context::new(&mut target, &mut state, &tz);
        let _ = program.resolve(&mut ctx);
    }

    // Benchmark
    let start = Instant::now();
    for _ in 0..iterations {
        let mut target = TargetValue {
            value: input.clone(),
            metadata: value::Value::Object(BTreeMap::new()),
            secrets: vrl::value::Secrets::default(),
        };
        let mut state = RuntimeState::default();
        let tz = TimeZone::default();
        let mut ctx = Context::new(&mut target, &mut state, &tz);
        let _ = program.resolve(&mut ctx);
    }
    let elapsed = start.elapsed();
    let per_iter_ns = elapsed.as_nanos() / iterations as u128;
    println!("{}: {} iterations in {:.3}ms ({} ns/iter)",
             name, iterations, elapsed.as_secs_f64() * 1000.0, per_iter_ns);
}

fn main() {
    let iterations: u64 = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(100_000);

    println!("=== Upstream Rust VRL Benchmark ({} iterations) ===\n", iterations);

    // Benchmark 1: Simple field assignment
    let input1 = value::Value::Object(BTreeMap::from([
        ("message".into(), value::Value::from("hello world")),
    ]));
    run_benchmark("field_assign", r#".environment = "production""#, input1, iterations);

    // Benchmark 2: String manipulation
    let input2 = value::Value::Object(BTreeMap::from([
        ("message".into(), value::Value::from("HELLO WORLD")),
    ]));
    run_benchmark("downcase", r#".message = downcase!(.message)"#, input2, iterations);

    // Benchmark 3: Conditional logic
    let input3 = value::Value::Object(BTreeMap::from([
        ("message".into(), value::Value::from("error: something broke")),
        ("level".into(), value::Value::from("info")),
    ]));
    run_benchmark("conditional", r#"
        if contains(string!(.message), "error") {
            .level = "error"
            .is_error = true
        } else {
            .level = "info"
            .is_error = false
        }
    "#, input3, iterations);

    // Benchmark 4: Multiple operations
    let input4 = value::Value::Object(BTreeMap::from([
        ("message".into(), value::Value::from("Hello World")),
        ("host".into(), value::Value::from("SERVER01")),
    ]));
    run_benchmark("multi_ops", r#"
        .message = downcase!(.message)
        .host = downcase!(.host)
        .env = "production"
        .processed = true
        del(.timestamp)
    "#, input4, iterations);

    // Benchmark 5: Arithmetic
    let input5 = value::Value::Object(BTreeMap::from([
        ("a".into(), value::Value::from(42)),
        ("b".into(), value::Value::from(13)),
    ]));
    run_benchmark("arithmetic", r#"
        .sum, err = .a + .b
        .diff, err = .a - .b
        .prod, err = .a * .b
    "#, input5, iterations);
}
