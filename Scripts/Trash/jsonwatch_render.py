#!/usr/bin/env python3
"""Scrollable live‑diff JSON viewer — **requires Textual ≥ 5.0**

* Watches a JSON file, highlights changed values in **yellow**.
* Scroll with **arrow keys, PgUp/PgDn, or *j*/*k***.
* A goblin 🧌 (or wizard 🧙‍♂️, pass ``w``) hops to a random changed row every 5 s.
* No backward‑compat shims: assumes you have the current ``textual`` & ``rich``.
"""

from __future__ import annotations

import json
import random
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Any, Dict

from rich.table import Table
from textual.app import App, ComposeResult
from textual.containers import Container
from textual.reactive import var
from textual.scroll_view import ScrollView  # Textual ≥ 5.0
from textual.widgets import Static

###############################################################################
# Helper
###############################################################################

def flatten(d: Any, prefix: str = "") -> Dict[str, str]:
    """Flatten nested dicts & lists, preserving insertion order."""
    if isinstance(d, dict):
        out: Dict[str, str] = {}
        for k, v in d.items():
            out.update(flatten(v, f"{prefix}{k} → "))
        return out
    if isinstance(d, list):
        out: Dict[str, str] = {}
        for i, v in enumerate(d):
            out.update(flatten(v, f"{prefix}{i} → "))
        return out
    return {prefix.rstrip(" → "): str(d)}

###############################################################################
# App
###############################################################################

class JsonWatchApp(App):
    """JSON diff viewer with smooth scrolling (Textual ≥ 5)."""

    BINDINGS = [
        ("7", "quit", "Quit"),
        ("3", "next_pane", "Next tmux pane"),
        ("k", "scroll_up", None),
        ("j", "scroll_down", None),
    ]  # arrows & PgUp/PgDn handled by ScrollView itself

    file_path: Path = var(Path("./Context/conjuration_log.json"))
    base_path: Path = var(Path("/tmp/conjuration_log.json"))
    creature: str = var("g")  # 'g' = goblin, 'w' = wizard

    refresh_s = 1.0
    hop_s = 5.0
    key_frac = 0.35  # width fraction for key column

    # ------------------------------------------------------------------
    def compose(self) -> ComposeResult:
        self.scroll = ScrollView()
        yield Container(self.scroll)

    async def on_mount(self) -> None:
        # Table container
        self.table_static = Static()
        await self.scroll.mount(self.table_static)
        self.set_focus(self.scroll)  # give keyboard focus

        # Baseline snapshot
        try:
            self.base_path.write_bytes(self.file_path.read_bytes())
        except FileNotFoundError:
            self.table_static.update(f"[red]File not found:[/red] {self.file_path}")
            return

        with self.base_path.open() as f:
            self._baseline = flatten(json.load(f))

        self._current: Dict[str, str] = {}
        self._creature_key: str | None = None

        # Draw & timers
        self.refresh_table()
        self.set_interval(self.refresh_s, self.refresh_table)
        self.set_interval(self.hop_s, self.jump_creature)

    # ------------------------ actions ---------------------------------
    def action_next_pane(self) -> None:
        subprocess.run(["tmux", "select-pane", "-t", ":.+"], check=False)

    def action_scroll_up(self) -> None:
        self.scroll.action_scroll_up()

    def action_scroll_down(self) -> None:
        self.scroll.action_scroll_down()

    # ----------------------- table logic ------------------------------
    def _build_table(self) -> Table:
        term_w = self.size.width or 120
        key_w = int(term_w * self.key_frac)
        val_w = term_w - key_w - 4

        tbl = Table(expand=True, show_header=True, header_style="bold")
        tbl.add_column("Key", style="cyan", no_wrap=True, width=key_w)
        tbl.add_column("Value", width=val_w, overflow="fold")

        emoji = "🧙‍♂️" if self.creature == "w" else "🧌"
        for k, v in self._current.items():
            changed = self._baseline.get(k) != v
            tag = emoji if changed and k == self._creature_key else ""
            wrapped = textwrap.fill(f"{v}{tag}", val_w)
            tbl.add_row(k, f"[yellow]{wrapped}[/yellow]" if changed else wrapped)
        return tbl

    def refresh_table(self) -> None:
        keep_y = self.scroll.y
        try:
            with self.file_path.open() as f:
                self._current = flatten(json.load(f))
        except Exception as exc:
            self.table_static.update(f"[red]Error:[/red] {exc}")
            return
        self.table_static.update(self._build_table())
        self.call_after_refresh(lambda: self.scroll.scroll_to(y=keep_y, animate=False))

    # ------------------- creature hop ---------------------------------
    def jump_creature(self) -> None:
        changed = [k for k, v in self._current.items() if self._baseline.get(k) != v]
        self._creature_key = random.choice(changed) if changed else None
        self.refresh_table()

# entry ----------------------------------------------------------------------
if __name__ == "__main__":
    if len(sys.argv) > 1:
        JsonWatchApp.file_path = Path(sys.argv[1])
    if len(sys.argv) > 2:
        JsonWatchApp.creature = sys.argv[2].lower()[:1]
    JsonWatchApp().run()
