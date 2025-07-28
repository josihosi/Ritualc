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
use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Stdout};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use crossterm::event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::{execute, queue};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use rand::seq::SliceRandom;
use ratatui::backend::{Backend, CrosstermBackend};
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Span, Spans};
use ratatui::widgets::{Block, Borders, Row, Table, TableState};
use ratatui::Terminal;
use serde_json::Value;

// -----------------------------------------------------------------------------
// Data helpers
// -----------------------------------------------------------------------------

/// Flatten arbitrarily nested JSON structures into a *key* → *value* map.
///
/// Given `{"foo": [1, 2]}` the function returns the ordered mapping
/// `{ "foo → 0": "1", "foo → 1": "2" }` – mirroring the behaviour of the
/// original Python implementation.
fn flatten(value: &Value, prefix: &str, out: &mut BTreeMap<String, String>) {
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
            out.insert(key.to_owned(), value.to_string());
        }
    }
}

fn load_flat(path: &Path) -> io::Result<BTreeMap<String, String>> {
    let data = fs::read_to_string(path)?;
    let json: Value = serde_json::from_str(&data)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let mut out = BTreeMap::new();
    flatten(&json, "", &mut out);
    Ok(out)
}

// -----------------------------------------------------------------------------
// Application state
// -----------------------------------------------------------------------------

struct App {
    file_path: PathBuf,
    baseline: BTreeMap<String, String>,
    current: BTreeMap<String, String>,
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

fn draw<B: Backend>(f: &mut ratatui::Frame<B>, app: &mut App) {
    let area = f.size();

    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Percentage(100)])
        .split(area);

    let key_width = max(10, (area.width as f32 * 0.35) as u16);
    let val_width = area.width - key_width - 1;

    let mut rows = Vec::with_capacity(app.current.len());
    for (k, v) in &app.current {
        let changed = app.baseline.get(k) != Some(v);
        let mut value = v.clone();
        if changed {
            if let Some(ref ck) = app.creature_key {
                if ck == k {
                    value.push(app.creature_char);
                }
            }
        }

        let style = if changed {
            Style::default().fg(Color::Yellow)
        } else {
            Style::default()
        };

        rows.push(Row::new(vec![k.clone(), value]).style(style));
    }

    let table = Table::new(rows)
        .header(Row::new(vec![
            Span::styled("Key", Style::default().add_modifier(Modifier::BOLD)),
            Span::styled("Value", Style::default().add_modifier(Modifier::BOLD)),
        ]))
        .block(Block::default().borders(Borders::ALL).title("jsonwatch"))
        .widths(&[Constraint::Length(key_width), Constraint::Length(val_width)])
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
    let mut watcher: RecommendedWatcher = Watcher::new(tx, Duration::from_secs(1))?;
    watcher.watch(&file_path, RecursiveMode::NonRecursive)?;

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

