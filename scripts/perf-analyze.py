"""Summarise a trace recorded by scripts/perf-record.sh: commit durations (the hitch proxy), hangs, SwiftUI updates and the
hottest symbols in our code.

    python3 -I scripts/perf-analyze.py .build/perf/history-Time-Profiler.trace [--window <from-s> <to-s>]

The call tree is saved next to the trace as "<name>.calltree.md".
"""

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

trace = Path(sys.argv[1])
base = trace.with_suffix("")
# Optional: restrict the Time Profiler tables to a window (seconds of trace time), e.g. to explain one slow commit.
WINDOW = []
if "--window" in sys.argv:
    t0, t1 = (float(v) for v in sys.argv[sys.argv.index("--window") + 1 : sys.argv.index("--window") + 3])
    WINDOW = ["--time-start", f"{int(t0 * 1000)}ms", "--duration", f"{int((t1 - t0) * 1000)}ms"]


def show(args):
    return subprocess.run(["xctrace", "show", "--input", str(trace)] + args, capture_output=True, text=True).stdout


def dur_ms(text):
    m = re.match(r"\s*([\d.,]+)\s*(ns|µs|us|ms|s|min)", text)
    if not m:
        return 0.0
    v = float(m.group(1).replace(",", ""))
    return v * {"ns": 1e-6, "µs": 1e-3, "us": 1e-3, "ms": 1.0, "s": 1000.0, "min": 60000.0}[m.group(2)]


def ts_s(text):
    m = re.match(r"\s*(\d+):(\d+)\.(\d+)\.(\d+)", text)
    return int(m.group(1)) * 60 + int(m.group(2)) + int(m.group(3)) / 1e3 + int(m.group(4)) / 1e6 if m else 0.0


# ---- Core Animation Commits: app-side commit durations stand in for hitches (Hitches is unsupported on the simulator).
print("=== Core Animation Commits")
commits = []
for line in show(["--track", "Core Animation Commits", "--list", "Intervals"]).splitlines()[1:]:
    cells = line.split("\t")
    if len(cells) >= 2 and re.match(r"\s*\d+:\d+", cells[0]):
        commits.append((ts_s(cells[0]), dur_ms(cells[1])))
busy = [c for c in commits if c[1] > 0.5]
if commits:
    print(f"commits: {len(commits)} total, {len(busy)} longer than 0.5 ms")
    print("  (budget: 16.67 ms at 60 Hz, 8.33 ms at 120 Hz)")
    for limit in (8.33, 16.67, 33.3, 50, 100, 250):
        over = [d for _, d in commits if d > limit]
        print(f"  > {limit:>6} ms: {len(over):5d}   (total {sum(over):8.0f} ms)")
    print("worst 12 commits (trace seconds, ms):")
    for t, d in sorted(commits, key=lambda r: -r[1])[:12]:
        print(f"  t={t:7.2f}s  {d:8.2f} ms")
else:
    print("no commit rows")

print("\n=== Hangs")
print(show(["--track", "Hangs", "--list", "Hangs"])[:1500].rstrip() or "(none)")

print("\n=== SwiftUI (Long Updates / All Updates)")
for name in ("Summary: Long Updates", "Summary: All Updates"):
    out = show(["--track", "SwiftUI", "--summary", name]).strip()
    print(f"-- {name}\n{out[:2500] if out else '(no data)'}")

# ---- Time Profiler: our frames are the ones in library "Workouts" (WorkoutsKit is linked statically into it).
print("\n=== Time Profiler (main thread)")
text = show(
    [
        "--track", "Time Profiler", "--calltree", "Profile", "--hide-heaviest-stack",
        "--arrange-columns", "Library Name|...", "--include-source-info", "--format", "markdown",
    ]
    + WINDOW
)
base.with_suffix(".window.calltree.md" if WINDOW else ".calltree.md").write_text(text)
loc_re = re.compile(r"^(.*?) \((/[^)]*?):(\d+)\)(?: \[disassembly\])?$")
rows = []  # (level, is_ours, weight_ms, self_ms, name, location, lib)
for line in text.splitlines():
    cells = line.split("|")
    if len(cells) < 8 or not cells[1].strip().isdigit():
        continue
    symbol = cells[6].strip()
    name, location = symbol, ""
    m = loc_re.match(symbol)
    if m:
        path = re.sub(r"^.*?/((?:Workouts|Packages)/)", r"\1", m.group(2))
        name, location = m.group(1), f"{path}:{m.group(3)}"
    rows.append(
        (int(cells[1]), cells[3].strip() == "Workouts", dur_ms(cells[4]), dur_ms(cells[5]), name, location, cells[3].strip())
    )
print(f"{len(rows)} call-tree rows")

# Framework frames worth a number of their own (inclusive main-thread time, outermost occurrence only).
PROBES = {
    "Core Animation commit (CA::Transaction::commit)": re.compile(r"CA::Transaction::commit\("),
    "SwiftUI graph update (AG::Graph::UpdateStack::update)": re.compile(r"AG::Graph::UpdateStack::update"),
    "SwiftUI view body (ViewGraph / GraphHost flush)": re.compile(r"GraphHost.flushTransactions|ViewGraph.updateOutputs"),
    "UIKit layoutSubviews": re.compile(r"layoutSubviews"),
    "UICollectionView dequeue / cell config": re.compile(r"dequeueReusable|_dequeueReusableViewOfKind|configureCell"),
    "UIKit touch / event handling": re.compile(r"_UIApplicationHandleEventQueue|UIApplicationHandleEvent"),
    "SwiftData fetch / faulting": re.compile(r"NSManagedObjectContext.*(execute|fetch)|_PFFaultHandler|-\[NSManagedObject .*willAccessValue"),
    "Swift Charts": re.compile(r"SwiftUICharts|Charts\."),
}
probe = defaultdict(float)
stack = []
incl = defaultdict(float)
attributed = defaultdict(float)
selfw = defaultdict(float)
where = {}
in_main = False
cpu_main = 0.0
for level, ours, weight, self_ms, name, loc, lib in rows:
    if level == 2:
        in_main = name.startswith("Main Thread")
    stack = stack[: level - 1]
    stack.append((name, ours))
    if not in_main or level < 3:
        continue
    cpu_main += self_ms
    if ours and "$main" not in name and name != "main":
        if loc:
            where.setdefault(name, loc)
        if not any(n == name and o for n, o in stack[:-1]):
            incl[name] += weight
    for label, pattern in PROBES.items():
        if pattern.search(name) and not any(pattern.search(n) for n, _ in stack[:-1]):
            probe[label] += weight
    owner = next((n for n, o in reversed(stack) if o and "$main" not in n and n != "main"), None)
    if owner:
        attributed[owner] += self_ms
    selfw[name if ours else f"(system) {lib}"] += self_ms

print(f"main thread sampled CPU: {cpu_main / 1000:.1f}s; of which under a frame of ours: {sum(attributed.values()) / 1000:.1f}s")


def table(title, data, n):
    print(f"\n{title}")
    for name, w in sorted(data.items(), key=lambda x: -x[1])[:n]:
        print(f"  {w / 1000:7.2f}s  {name[:130]}  [{where.get(name, '')}]")


print("\ninclusive main-thread time of framework probes:")
for label, w in sorted(probe.items(), key=lambda x: -x[1]):
    print(f"  {w / 1000:7.2f}s  {label}")
table("top 30 of OUR symbols by inclusive main-thread time (includes callees):", incl, 30)
table("view bodies (inclusive; SwiftUI instrument data is unavailable on the simulator):", {k: v for k, v in incl.items() if "body.getter" in k}, 10)
table("top 20 of OUR symbols by time attributed (self + system callees below the deepest frame of ours):", attributed, 20)
table("top 14 leaf buckets (ours by symbol, everything else pooled per library):", selfw, 14)
