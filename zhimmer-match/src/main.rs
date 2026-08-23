//! zhimmer-match -- candidate generator for the zhimmer zsh plugin.
//!
//! Reads a zsh history file, prefix-filters it against a query, ranks by
//! frecency, and prints one candidate per line. The zsh side feeds this output
//! to `compadd`; rendering stays in zsh because `compadd` only exists inside a
//! completion widget.

mod history;
mod rank;

use std::io::{self, Read, Write};
use std::process::ExitCode;

const USAGE: &str = "usage: zhimmer-match [--history PATH] [--limit N] [QUERY]";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();

    let mut path = std::env::var("HISTFILE").unwrap_or_default();
    let mut limit: usize = 10;
    let mut query = String::new();

    let mut it = args.into_iter();
    let mut flags_done = false;
    while let Some(a) = it.next() {
        if flags_done {
            query = a;
            continue;
        }
        match a.as_str() {
            // Everything after `--` is the query. Without this, a user typing
            // `-h` or `--limit` at the prompt would hit the flag parser.
            "--" => flags_done = true,
            "--history" => match it.next() {
                Some(v) => path = v,
                None => return fail("--history needs a path"),
            },
            "--limit" => match it.next().and_then(|v| v.parse().ok()) {
                Some(v) => limit = v,
                None => return fail("--limit needs a number"),
            },
            "-h" | "--help" => {
                println!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            _ => query = a,
        }
    }

    if path.is_empty() {
        return fail("no history file: pass --history or set HISTFILE");
    }

    // Read as bytes: zsh history is not guaranteed to be valid UTF-8, and a
    // stray byte in one old entry must not take down the whole dropdown.
    let mut buf = Vec::new();
    match std::fs::File::open(&path).and_then(|mut f| f.read_to_end(&mut buf)) {
        Ok(_) => {}
        Err(e) => return fail(&format!("{path}: {e}")),
    }
    let raw = String::from_utf8_lossy(&buf);

    let entries = history::parse(&raw);
    let out = rank::rank(&entries, &query, limit);

    let mut stdout = io::stdout().lock();
    for c in out {
        // Ignore broken-pipe: zsh may close the pipe early on a fast keystroke.
        if writeln!(stdout, "{c}").is_err() {
            break;
        }
    }
    ExitCode::SUCCESS
}

fn fail(msg: &str) -> ExitCode {
    eprintln!("zhimmer-match: {msg}\n{USAGE}");
    ExitCode::FAILURE
}
