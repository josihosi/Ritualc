#!/usr/bin/env python3
import sys, json, time, os, math, random
from contextlib import contextmanager          # <<< NEW
from rich.table import Table
from rich.console import Console
from rich.live import Live

# ---------- platform‑agnostic key reader ------------------------
def _nop(): return None

try:                                  # ── POSIX ────────────────
    import termios, tty, select
    def _posix_read_key():
        fd = sys.stdin.fileno()
        if not select.select([fd], [], [], 0)[0]:
            return None
        ch1 = sys.stdin.read(1)
        if ch1 != '\x1b':
            return ch1
        if select.select([fd], [], [], 0)[0] and sys.stdin.read(1) == '[':
            ch3 = sys.stdin.read(1) if select.select([fd], [], [], 0)[0] else ''
            return {'C': 'RIGHT', 'D': 'LEFT'}.get(ch3)
        return None

    @contextmanager
    def raw_mode_if_tty():
        if not sys.stdin.isatty():
            yield; return
        fd, prev = sys.stdin.fileno(), termios.tcgetattr(sys.stdin.fileno())
        try:
            tty.setcbreak(fd); yield
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, prev)

    read_key = _posix_read_key if sys.stdin.isatty() else _nop

except ImportError:                     # ── Windows ─────────────
    import msvcrt
    def _win_read_key():
        if not msvcrt.kbhit(): return None
        ch = msvcrt.getwch()
        if ch in ('\x00', '\xe0'):           # arrows / Fn keys
            code = msvcrt.getwch()
            return {'M': 'RIGHT', 'K': 'LEFT'}.get(code)
        return ch
    read_key = _win_read_key if sys.stdin.isatty() else _nop

    @contextmanager
    def raw_mode_if_tty():
        yield                                 # nothing extra

# ---------- helpers --------------------------------------------
def flatten(d, prefix=''):
    if isinstance(d, dict):
        return {k2: v2 for k, v in d.items()
                for k2, v2 in flatten(v, f"{prefix}{k} → ").items()}
    if isinstance(d, list):
        return {k2: v2 for i, v in enumerate(d)
                for k2, v2 in flatten(v, f"{prefix}{i} → ").items()}
    return {prefix.rstrip(" → "): str(d)}

def make_table(curr, base, page, page_size, goblin_key=None):
    keys      = list(curr.keys())
    total_pg  = max(1, math.ceil(len(keys) / page_size))
    start, end = page * page_size, (page + 1) * page_size

    tbl = Table(
        title=f"📜 Conjuration Snapshot [n/p a/d ←/→] — page {page+1}/{total_pg}",
        expand=True,
    )
    tbl.add_column("Key", style="bold cyan", no_wrap=True)
    tbl.add_column("Value", justify="left")

    for k in keys[start:end]:
        val = curr[k]
        if base.get(k) != val:
            # highlight changed values; show goblin at its current key
            if goblin_key is not None and k == goblin_key:
                display = f"{val} 👺"
            else:
                display = val
            tbl.add_row(k, f"[yellow]{display}[/yellow]")
        else:
            tbl.add_row(k, val)
    return tbl

# ---------- main -----------------------------------------------
FILE = sys.argv[1] if len(sys.argv) > 1 else './Context/conjuration_log.json'
BASE = sys.argv[2] if len(sys.argv) > 2 else '/tmp/jsonwatch_baseline.json'
page_size, page = 20, 0

with open(FILE) as f: current = flatten(json.load(f))
if os.path.exists(BASE):
    with open(BASE) as f: baseline = flatten(json.load(f))
else:
    baseline = current.copy()
    with open(BASE, "w") as f: json.dump(baseline, f)

console = Console()

with raw_mode_if_tty():                       # <<< use new CM
    # initialize goblin jump state
    goblin_key = None
    last_goblin_jump = time.time()
    try:
        with Live(make_table(current, baseline, page, page_size, goblin_key),
                  console=console, refresh_per_second=2, screen=True) as live:

            while True:
                time.sleep(0.1)
                key = read_key()
                if key in ('n', 'a', 'RIGHT'):
                    page = (page + 1) % max(1, math.ceil(len(current)/page_size))
                elif key in ('p', 'd', 'LEFT'):
                    page = (page - 1) % max(1, math.ceil(len(current)/page_size))
                elif key == 'q':
                    break

                with open(FILE) as f:
                    current = flatten(json.load(f))
                # update goblin position every 5 seconds among changed keys
                now = time.time()
                if now - last_goblin_jump >= 5:
                    changed = [k for k, v in current.items() if baseline.get(k) != v]
                    goblin_key = random.choice(changed) if changed else None
                    last_goblin_jump = now
                live.update(make_table(current, baseline, page, page_size, goblin_key))

    except KeyboardInterrupt:                # <<< correct scope
        pass
