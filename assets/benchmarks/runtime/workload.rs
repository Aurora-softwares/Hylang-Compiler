use std::env;

fn loop_workload(n: i64) -> i64 {
    let mut state: i64 = 1;
    let mut checksum: i64 = 0;
    let mut i: i64 = 0;
    while i < n {
        state = (state * 17 + (i % 13) + 11) % 1_000_003;
        checksum += state % 97;
        i += 1;
    }
    checksum
}

fn array_workload(n: i64) -> i64 {
    let mut values = vec![0_i64; n as usize];
    let mut i: i64 = 0;
    while i < n {
        values[i as usize] = (i * 17 + 3) % 1_000_003;
        i += 1;
    }
    let mut checksum: i64 = 0;
    i = 0;
    while i < n {
        checksum += values[i as usize] % 97;
        i += 1;
    }
    checksum
}

fn file_workload(mode: &str, path: &str) -> i64 {
    let data = std::fs::read(path).expect("read input");
    if mode == "log" {
        let (mut errors, mut lines, mut at_start) = (0_i64, 0_i64, true);
        for &ch in &data {
            if at_start && ch == b'E' { errors += 1; }
            if ch == b'\n' { lines += 1; at_start = true; }
            else { at_start = false; }
        }
        errors * 97 + lines
    } else if mode == "csv" {
        let (mut amount, mut rows, mut sum, mut in_amount) = (0_i64, 0_i64, 0_i64, false);
        for &ch in &data {
            if ch == b',' { in_amount = true; }
            else if ch == b'\n' { sum += amount; rows += 1; amount = 0; in_amount = false; }
            else if in_amount { amount = amount * 10 + (ch - b'0') as i64; }
        }
        sum + rows * 3
    } else {
        let mut checksum = 0_i64;
        for &ch in &data { checksum = (checksum * 33 + ch as i64) % 1_000_003; }
        checksum
    }
}

struct Node { value: i64, next: Option<Box<Node>> }

fn nodes_workload(n: i64) -> i64 {
    let mut head: Option<Box<Node>> = None;
    for i in 0..n { head = Some(Box::new(Node { value: i % 97, next: head })); }
    let mut checksum = 0_i64;
    let mut current = head.as_ref();
    while let Some(item) = current { checksum += item.value; current = item.next.as_ref(); }
    // All routes retain the list until process exit.
    std::mem::forget(head);
    checksum
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        std::process::exit(2);
    }
    if matches!(args[1].as_str(), "log" | "csv" | "bytes") {
        println!("{}", file_workload(&args[1], &args[2]));
        return;
    }
    let n: i64 = args[2].parse().unwrap_or(0);
    if n < 1 {
        std::process::exit(2);
    }
    let checksum = match args[1].as_str() {
        "loop" => loop_workload(n),
        "array" => array_workload(n),
        "nodes" => nodes_workload(n),
        _ => std::process::exit(2),
    };
    println!("{checksum}");
}
