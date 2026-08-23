//! Parsing of zsh's plain (non-extended) history format.

/// Yield the complete, single-line commands in a raw history file.
///
/// zsh stores a command containing a newline by ending the physical line with a
/// backslash, so a naive line split yields fragments -- the user's history has
/// 254 such continuations, which would otherwise surface as candidates like a
/// bare `\` or an indented sentence. Multi-line commands are skipped outright
/// rather than joined: a candidate containing a newline cannot be rendered in a
/// completion listing anyway, so joining them would only cost allocations.
///
/// Borrows from `raw` -- this runs on every keystroke, so it must not allocate
/// per entry.
pub fn parse(raw: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut skipping = false;

    for line in raw.lines() {
        let cont = continues(line);
        if skipping {
            // Inside a multi-line command; discard until it ends.
            skipping = cont;
            continue;
        }
        if cont {
            skipping = true;
        } else if !line.is_empty() {
            out.push(line);
        }
    }
    out
}

/// A trailing backslash continues the command only when unescaped, i.e. when the
/// run of backslashes ending the line has odd length: `echo foo\\` ends a
/// command, `echo foo\` does not.
fn continues(line: &str) -> bool {
    line.bytes().rev().take_while(|&b| b == b'\\').count() % 2 == 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_lines_pass_through() {
        assert_eq!(parse("ls\ncd /tmp\n"), vec!["ls", "cd /tmp"]);
    }

    #[test]
    fn skips_multiline_commands_entirely() {
        // The shape actually found in the user's history: a bare `\` opening a
        // pasted block, then indented continuation lines. No fragment of this
        // may survive.
        let raw = "ls\n\\\n  git config --global user.email \"a@b.c\"\\\n  git config --global user.name \"N\"\ncd\n";
        assert_eq!(parse(raw), vec!["ls", "cd"]);
    }

    #[test]
    fn escaped_backslash_does_not_continue() {
        assert_eq!(parse("echo foo\\\\\nls\n"), vec!["echo foo\\\\", "ls"]);
    }

    #[test]
    fn unterminated_continuation_at_eof_is_dropped() {
        assert_eq!(parse("ls\necho a\\\n"), vec!["ls"]);
    }

    #[test]
    fn skips_blank_lines() {
        assert_eq!(parse("ls\n\n\ncd\n"), vec!["ls", "cd"]);
    }

    #[test]
    fn two_consecutive_multiline_commands() {
        assert_eq!(parse("a\\\nb\nc\\\nd\ne\n"), vec!["e"]);
    }
}
