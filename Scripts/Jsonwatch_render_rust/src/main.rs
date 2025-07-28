//------------------------------------------------------------------------------
// jsonwatch_render.rs – Rust re-implementation of *jsonwatch_render.py*
//------------------------------------------------------------------------------
//
// The program offers a **live, scroll-able diff view** for JSON files that is
// virtually identical to the original Python/Textual version:
//
//   * Watches a JSON file and refreshes the view once per second.
//   * Highlights values that differ from the initial snapshot **in yellow**.
//   * A goblin 🧌 (or wizard 🧙‍♂️ if «w» is passed) hops to a random changed
//     entry every 5 seconds.
//   * Smooth scrolling with *j* / *k*, arrow keys, PgUp / PgDn.
//   * Press «7» or «q» to quit, «3» jumps to the next *tmux* pane – exactly
//     like the Python version.
//
// It relies solely on battle-tested, *async-free* building blocks from the
// Rust eco-system:
//
//   – **crossterm**   for portable ANSI terminal I/O and keyboard handling.
//   – **ratatui**     (the tui-rs successor) for layout and widgets.
//   – **serde_json**  for robust JSON parsing.
//   – **notify**      to receive filesystem change events without polling.
//   – **rand**        to pick a random row for our little creature.
//
// The entire application fits into a single self-contained source file so
// creating a standalone binary is as simple as
//
//     $ rustc jsonwatch_render.rs $(pkg-config --libs --static ...)  # or
//     $ cargo run --release -- foo.json w
//
// (using the `Cargo.toml` from the repository root).  **No changes to the
// original CLI interface are required.**
//------------------------------------------------------------------------------

use std::cmp::max;
use indexmap::IndexMap;
use std::fs;
use std::io;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::execute;
use notify::{RecommendedWatcher, RecursiveMode, Watcher, Config};
use rand::seq::SliceRandom;
use ratatui::backend::CrosstermBackend;
use ratatui::{Frame, Terminal};
use ratatui::layout::{Alignment, Constraint, Direction, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Span, Line};
use ratatui::widgets::{Block, Borders, Cell, Row, Table, TableState};
use serde_json::Value;

// -----------------------------------------------------------------------------
// Data helpers
// -----------------------------------------------------------------------------

/// Flatten arbitrarily nested JSON structures into a *key* → *value* insertion-ordered map.
///
/// Given `{"foo": [1, 2]}` the function returns the ordered mapping
/// `{ "foo → 0": "1", "foo → 1": "2" }` – mirroring the behaviour of the
/// original Python implementation.
fn flatten(value: &Value, prefix: &str, out: &mut IndexMap<String, String>) {
    match value {
        Value::Object(map) => {
            for (k, v) in map {
                let new_prefix = if prefix.is_empty() {
                    format!("{k} → ")
                } else {
                    format!("{prefix}{k} → ")
                };
                flatten(v, &new_prefix, out);
            }
        }
        Value::Array(arr) => {
            for (idx, v) in arr.iter().enumerate() {
                let new_prefix = if prefix.is_empty() {
                    format!("{idx} → ")
                } else {
                    format!("{prefix}{idx} → ")
                };
                flatten(v, &new_prefix, out);
            }
        }
        _ => {
            let key = prefix.trim_end_matches(" → ");
            // For JSON strings, strip surrounding quotes and preserve actual content
            let content = if let Value::String(s) = value {
                s.clone()
            } else {
                value.to_string()
            };
            out.insert(key.to_owned(), content);
        }
    }
}

fn load_flat(path: &Path) -> io::Result<IndexMap<String, String>> {
    let data = fs::read_to_string(path)?;
    let json: Value = serde_json::from_str(&data)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let mut out = IndexMap::new();
    flatten(&json, "", &mut out);
    Ok(out)
}
// -----------------------------------------------------------------------------
// Text truncation and wrapping helpers
// -----------------------------------------------------------------------------
/// Truncate string `s` to `width` chars, adding "..." if truncated.
fn ellipsize(s: &str, width: usize) -> String {
    if width == 0 {
        return String::new();
    }
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= width {
        s.to_string()
    } else if width > 3 {
        let mut result = chars[..width - 3].iter().collect::<String>();
        result.push_str("...");
        result
    } else {
        ".".repeat(width)
    }
}


/// Wrap string `s` into lines no longer than `width` characters.
/// Wrap string `s` into lines no longer than `width` characters,
/// adding hyphens on mid-word splits.
fn wrap_to_lines(s: &str, width: usize) -> Vec<String> {
    if width == 0 {
        return vec![String::new()];
    }
    let mut lines = Vec::new();
    // Process each paragraph (split on explicit newlines)
    for segment in s.split('\n') {
        if segment.is_empty() {
            lines.push(String::new());
            continue;
        }
        let chars: Vec<char> = segment.chars().collect();
        let mut idx = 0;
        let len = chars.len();
        let mut seg_lines = Vec::new();
        while idx < len {
            let rem = len - idx;
            if rem <= width {
                // Last line of this segment
                let last_line: String = chars[idx..].iter().collect();
                seg_lines.push(last_line);
                break;
            }
            // Need to wrap
            let slice = &chars[idx..idx + width];
            // Find last whitespace in slice
            let split_pos = slice.iter().rposition(|c| c.is_whitespace());
            if let Some(pos) = split_pos {
                if pos == 0 {
                    // No leading word before space, hyphenate
                    let take = width - 1;
                    let mut line: String = chars[idx..idx + take].iter().collect();
                    line.push('-');
                    seg_lines.push(line.clone());
                    idx += take;
                } else {
                    // Break at word boundary
                    let line: String = slice[..pos].iter().collect();
                    seg_lines.push(line.clone());
                    // Skip whitespace
                    idx += pos + 1;
                }
            } else {
                // No whitespace, hyphenate
                let take = width - 1;
                let mut line: String = chars[idx..idx + take].iter().collect();
                line.push('-');
                seg_lines.push(line.clone());
                idx += take;
            }
        }
        // Add all wrapped lines (hyphenation applies, no justification)
        for line in seg_lines {
            lines.push(line);
        }
    }
    if lines.is_empty() {
        lines.push(String::new());
    }
    lines
}

// -----------------------------------------------------------------------------
// Application state
// -----------------------------------------------------------------------------

struct App {
    file_path: PathBuf,
    baseline: IndexMap<String, String>,
    current: IndexMap<String, String>,
    creature_key: Option<String>,
    creature_char: char, // 🧌 or 🧙‍♂️
    last_hop: Instant,
    hop_every: Duration,
    table_state: TableState,
}

impl App {
    fn new(file_path: PathBuf, creature_char: char) -> io::Result<Self> {
        // The Python version stores a baseline snapshot under /tmp to avoid
        // modifying the original file – we keep things simple and load the
        // baseline directly here.
        let baseline = load_flat(&file_path)?;

        Ok(Self {
            current: baseline.clone(),
            baseline,
            file_path,
            creature_key: None,
            creature_char,
            last_hop: Instant::now(),
            hop_every: Duration::from_secs(5),
            table_state: TableState::default(),
        })
    }

    /// Reload the file if it changed and update the *current* map.
    fn refresh(&mut self) {
        if let Ok(curr) = load_flat(&self.file_path) {
            self.current = curr;
        }

        if self.last_hop.elapsed() >= self.hop_every {
            let changed: Vec<_> = self
                .current
                .iter()
                .filter(|(k, v)| self.baseline.get(*k) != Some(*v))
                .map(|(k, _)| k.clone())
                .collect();

            if let Some(choice) = changed.choose(&mut rand::thread_rng()) {
                self.creature_key = Some(choice.clone());
            }
            self.last_hop = Instant::now();
        }
    }
}

// -----------------------------------------------------------------------------
// UI rendering helpers
// -----------------------------------------------------------------------------

fn draw<'a>(f: &mut Frame<'a>, app: &mut App) {
    let area = f.size();
    // (Padding column removed)
    // Single vertical layout covering full area
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Percentage(100)])
        .split(area);
    // Compute column widths: key, value, padding
    let key_width = max(10, (area.width as f32 * 0.35) as u16);
    // Subtract key column, padding column, borders (2 chars), and column spacing (2 spaces)
    let val_width = area.width.saturating_sub(key_width + 4);

    let mut rows = Vec::with_capacity(app.current.len());
    for (k, v) in &app.current {
        let changed = app.baseline.get(k) != Some(v);
        // Truncate key with ellipsis
        let key_text = if k.chars().count() > key_width as usize {
            ellipsize(k, key_width as usize)
        } else {
            k.clone()
        };
        // Style key: cyan by default, yellow if changed
        let key_style = if changed {
            Style::default().fg(Color::Yellow)
        } else {
            Style::default().fg(Color::Cyan)
        };
        // Prepare key cell as a right-aligned single-line styled content
        let key_lines = vec![
            Line::styled(key_text, key_style)
                .alignment(Alignment::Right)
        ];
        // Wrap and style value
        let raw_value = v.clone();
        let mut wrapped = wrap_to_lines(&raw_value, val_width as usize);
        if changed {
            if let Some(ref ck) = app.creature_key {
                if ck == k {
                    if let Some(last) = wrapped.last_mut() {
                        last.push(app.creature_char);
                    }
                }
            }
        }
        let row_height = wrapped.len().max(1) as u16;
        let val_style = if changed {
            Style::default().fg(Color::Yellow)
        } else {
            Style::default()
        };
        // Prepare value lines with wrapping and styling (left-aligned by default)
        let val_lines = wrapped
            .into_iter()
            .map(|line| Line::styled(line, val_style))
            .collect::<Vec<Line>>();
        // add empty padding cell
        rows.push(
            // Create a row with key and value columns
            Row::new(vec![key_lines, val_lines])
                .height(row_height)
        );
    }

    // Build table with key and value columns
    let table = Table::new(
        rows,
        vec![
            Constraint::Length(key_width),
            Constraint::Length(val_width),
        ],
    )
    .header(
        // Header row with right-aligned key, left-aligned value
        Row::new(vec![
            vec![Line::styled("Key", Style::default().add_modifier(Modifier::BOLD))
                .alignment(Alignment::Right)],
            vec![Line::styled("Value", Style::default().add_modifier(Modifier::BOLD))],
        ])
    )
    .block(Block::default().borders(Borders::ALL).title("📜 Conjuration log [Pg Up / Pg Down] [3: Switch Pane / 7: Exit]"))
    .column_spacing(1);

    f.render_stateful_widget(table, layout[0], &mut app.table_state);
}

// -----------------------------------------------------------------------------
// Keyboard helpers – mirrors the semantics of the Python version
// -----------------------------------------------------------------------------

fn scroll_relative(app: &mut App, dy: i64) {
    let len = app.current.len() as i64;
    let sel = app.table_state.selected().unwrap_or(0) as i64;
    let new = (sel + dy).clamp(0, len.saturating_sub(1));
    app.table_state.select(Some(new as usize));
}

fn page_height(term_rows: u16) -> i64 {
    (term_rows.saturating_sub(1)) as i64
}

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------

fn main() -> io::Result<()> {
    // ---------------------------------------------------------------------
    // CLI parsing (identical to Python version)
    // ---------------------------------------------------------------------
    let mut argv = std::env::args().skip(1);
    let file_path = argv
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("./Context/conjuration_log.json"));

    let creature = match argv.next().unwrap_or_default().to_lowercase().chars().next() {
        Some('w') => '🧙',
        _ => '🧌',
    };

    // ---------------------------------------------------------------------
    // Application set-up – terminal, file-watcher, state …
    // ---------------------------------------------------------------------
    let mut app = App::new(file_path.clone(), creature)?;

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // ---------------------------------------------------------------------
    // File watcher
    // ---------------------------------------------------------------------
    let (tx, rx) = std::sync::mpsc::channel();
    let mut watcher: RecommendedWatcher = Watcher::new(tx, Config::default())
        .map_err(|e| io::Error::new(ErrorKind::Other, e))?;
    watcher.watch(&file_path, RecursiveMode::NonRecursive)
        .map_err(|e| io::Error::new(ErrorKind::Other, e))?;

    // ---------------------------------------------------------------------
    // Main event-loop
    // ---------------------------------------------------------------------
    loop {
        // Draw UI
        terminal.draw(|f| draw(f, &mut app))?;

        // Wait for *either* a user input *or* a file-system change.
        // We cap the poll duration to 250 ms to ensure timely hops of the
        // little creature.
        if event::poll(Duration::from_millis(250))? {
            match event::read()? {
                Event::Key(key) => match key.code {
                    // ----- quit ------------------------------------------------
                    KeyCode::Char('q') | KeyCode::Char('7') => break,

                    // ----- scrolling (vim style) ------------------------------
                    KeyCode::Char('j') => scroll_relative(&mut app, (terminal.size()?.height as f32 * 0.10) as i64),
                    KeyCode::Char('k') => scroll_relative(&mut app, -((terminal.size()?.height as f32 * 0.10) as i64)),

                    // ----- page up / down -------------------------------------
                    KeyCode::PageDown => scroll_relative(&mut app, page_height(terminal.size()?.height)),
                    KeyCode::PageUp => scroll_relative(&mut app, -page_height(terminal.size()?.height)),

                    // ----- next tmux pane -------------------------------------
                    KeyCode::Char('3') => {
                        let _ = std::process::Command::new("tmux")
                            .args(["select-pane", "-t", ":.+"])
                            .spawn();
                    }
                    _ => {}
                },
                // Ignore resize events – ratatui handles them automatically on
                // the next draw call.
                Event::Resize(_, _) => {}
                _ => {}
            }
        }

        // File changed → reload & refresh creature hop timer.
        while let Ok(_) = rx.try_recv() {
            app.refresh();
        }

        // Even without file changes we still need to hop.
        app.refresh();
    }

    // ---------------------------------------------------------------------
    // Clean-up
    // ---------------------------------------------------------------------
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    Ok(())
}
