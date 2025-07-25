#!/usr/bin/env python3

import json, time, os, sys, hashlib
from rich.table import Table
from rich.console import Console
from rich import print

def flatten(d, prefix=''):
    result = {}
    if isinstance(d, dict):
        for k, v in d.items():
            result.update(flatten(v, f'{prefix}{k} → '))
    elif isinstance(d, list):
        for i, v in enumerate(d):
            result.update(flatten(v, f'{prefix}{i} → '))
    else:
        result[prefix.rstrip(' → ')] = str(d)
    return result

def get_hash(path):
    with open(path, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()

def build_table(data, baseline):
    table = Table(show_lines=True)
    table.add_column("Key", style="cyan", no_wrap=True)
    table.add_column("Value")

    for k, v in data.items():
        if baseline.get(k) != v:
            table.add_row(k, f"[yellow]{v}[/yellow]")
        else:
            table.add_row(k, v)
    return table

FILE = sys.argv[1] if len(sys.argv) > 1 else './Context/conjuration_log.json'
console = Console()
last_hash = None
baseline = {}

while True:
    try:
        new_hash = get_hash(FILE)
        if new_hash != last_hash:
            with open(FILE) as f:
                current = flatten(json.load(f))
            if not baseline:
                baseline = current.copy()
            table = build_table(current, baseline)
            with open("/tmp/.jsonwatch_render.txt", "w") as tmp:
                console = Console(file=tmp, force_terminal=True, width=120)
                console.print(table)
            os.system("clear && less -R /tmp/.jsonwatch_render.txt")
            last_hash = new_hash
        time.sleep(1)
    except KeyboardInterrupt:
        break
