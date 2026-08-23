//! Prefix filtering and frecency ranking.

use std::collections::HashMap;

/// Rank history entries matching `query` as a prefix, best first.
///
/// The history file carries no timestamps (zsh only writes them under
/// EXTENDED_HISTORY), so recency is approximated by position: the later an entry
/// last appears, the more recent it is. Frequency is its duplicate count, which
/// is a strong signal here -- the user's history is ~69% duplicates.
pub fn rank(entries: &[&str], query: &str, limit: usize) -> Vec<String> {
    if entries.is_empty() || limit == 0 {
        return Vec::new();
    }
    let total = entries.len() as f64;

    // command -> (occurrences, index of last occurrence)
    let mut seen: HashMap<&str, (u32, usize)> = HashMap::new();
    for (i, &e) in entries.iter().enumerate() {
        if !e.starts_with(query) || e == query {
            continue;
        }
        let slot = seen.entry(e).or_insert((0, i));
        slot.0 += 1;
        slot.1 = i;
    }

    let mut scored: Vec<(f64, usize, &str)> = seen
        .iter()
        .map(|(&cmd, &(count, last))| (score(count, last, total), last, cmd))
        .collect();

    // Highest score first; ties broken by whichever was run most recently.
    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap().then(b.1.cmp(&a.1)));
    scored.truncate(limit);
    scored.into_iter().map(|(_, _, c)| c.to_string()).collect()
}

/// Frequency scaled by how recently the command last appeared. The newest entry
/// is worth 4x its count, the oldest 1x, interpolated linearly in between.
fn score(count: u32, last: usize, total: f64) -> f64 {
    count as f64 * (1.0 + 3.0 * (last as f64 / total))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filters_by_prefix() {
        let got = rank(&["git status", "ls -la", "git push"], "git ", 10);
        assert_eq!(got.len(), 2);
        assert!(got.iter().all(|c| c.starts_with("git ")));
    }

    #[test]
    fn frequency_beats_a_single_recent_run() {
        // "git status" ran 4x but earlier; "git stash drop" ran once, most recent.
        let h = ["git status", "git status", "git status", "git status", "git stash drop"];
        assert_eq!(rank(&h, "git s", 10)[0], "git status");
    }

    #[test]
    fn recency_breaks_ties_between_equal_counts() {
        // Equal counts, but "git pull" appears last.
        let h = ["git push", "git pull", "git push", "git pull"];
        assert_eq!(rank(&h, "git p", 10)[0], "git pull");
    }

    #[test]
    fn deduplicates() {
        assert_eq!(rank(&["ls", "ls", "ls"], "l", 10), vec!["ls"]);
    }

    #[test]
    fn excludes_exact_query_match() {
        // Suggesting what is already typed verbatim is noise.
        assert_eq!(rank(&["ls", "ls -la"], "ls", 10), vec!["ls -la"]);
    }

    #[test]
    fn respects_limit() {
        assert_eq!(rank(&["a1", "a2", "a3", "a4", "a5"], "a", 3).len(), 3);
    }

    #[test]
    fn empty_query_returns_everything_ranked() {
        assert_eq!(rank(&["b", "a", "a"], "", 10)[0], "a");
    }

    #[test]
    fn empty_history_is_not_a_panic() {
        assert!(rank(&[], "git", 10).is_empty());
    }
}
