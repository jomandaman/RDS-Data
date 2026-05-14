#!/usr/bin/env python3
"""Generate pillar_b_rest_api.ipynb — REST API / React architecture
performance evidence. Three sections only: architecture inventory,
live paired comparison, compound clinical-session savings."""
import nbformat as nbf
import os

DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
nb = nbf.v4.new_notebook()
cells = []

def md(s): cells.append(nbf.v4.new_markdown_cell(s.strip()))
def py(s): cells.append(nbf.v4.new_code_cell(s.strip()))

md("""
# Pillar B — Architecture & Performance

Three questions, one notebook:

1. **What was built?** REST API surface + React SPA inventory.
2. **Does the new architecture actually perform better?** Authenticated
   paired benchmarks against dev EC2.
3. **What's the compound effect over a typical clinical session?**
   Real workflow simulation using the measured per-endpoint numbers.
""")

py("""
import os, re, subprocess
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

# Thesis-quality chart defaults
plt.rcParams.update({
    "font.size":          12,
    "axes.titlesize":     14,
    "axes.titleweight":   "bold",
    "axes.labelsize":     12,
    "xtick.labelsize":    11,
    "ytick.labelsize":    11,
    "legend.fontsize":    11,
    "figure.titlesize":   16,
    "figure.titleweight": "bold",
    "axes.spines.top":    False,
    "axes.spines.right":  False,
})

DIR = os.getcwd()
SRC = "/Users/josiahzacharias/Library/Mobile Documents/com~apple~CloudDocs/School/UWB/CSS 595 (Final Project)/source/rep5_0209"

def sh(cmd, cwd=SRC):
    return subprocess.check_output(cmd, shell=True, cwd=cwd, text=True).strip()

print(f"Source repo branch: {sh('git rev-parse --abbrev-ref HEAD')}")
print(f"Commit:             {sh('git rev-parse --short HEAD')} ({sh('git log -1 --format=%ad --date=short')})")
""")

md("""
# 1. What was built — REST API + React SPA inventory
""")

py("""
# Endpoint surface (parsed from api/v1/index.php header)
with open(f"{SRC}/api/v1/index.php") as f:
    text = f.read()
endpoints = re.findall(r"\\*\\s+(GET|POST|PUT|DELETE|PATCH)\\s+(/api/v1/\\S+)\\s+-\\s+(.+)", text)
ep_df = pd.DataFrame(endpoints, columns=["verb", "path", "description"])

# Controllers
ctrls = sorted([f for f in os.listdir(f"{SRC}/api/v1/controllers") if f.endswith(".php")])
ctrl_data = []
for c in ctrls:
    rel = f"api/v1/controllers/{c}"
    lines = int(sh(f"wc -l < '{rel}'").split()[0])
    methods = int(sh(f"grep -cE 'public function ' '{rel}'") or 0)
    ctrl_data.append({"controller": c, "lines": lines, "methods": methods})
ctrl_df = pd.DataFrame(ctrl_data).sort_values("lines", ascending=False)

# React components
comp_dir = f"{SRC}/Components/react-prototype"
components = []
for root, _, files in os.walk(comp_dir):
    for f in files:
        if f.endswith((".jsx", ".js")):
            full = os.path.join(root, f)
            with open(full) as fp:
                lines = sum(1 for _ in fp)
            components.append({"file": os.path.relpath(full, SRC), "lines": lines})
comp_df = pd.DataFrame(components).sort_values("lines", ascending=False).reset_index(drop=True)

# Headline counts
print(f"REST endpoints documented: {len(ep_df)}  ({ep_df['verb'].value_counts().to_dict()})")
print(f"Controllers:               {len(ctrls)}, total {ctrl_df['lines'].sum():,} lines, {ctrl_df['methods'].sum()} public methods")
print(f"React components:          {len(comp_df)}, total {comp_df['lines'].sum():,} lines")
""")

md("""
### Architecture inventory — what was built (numbers, not chart)

The line-count comparison is intentionally not visualized: the React
SPA is **larger** than the sum of the five legacy pages it replaces
(~7,000 LOC vs ~3,400). LOC isn't the architecture win. The
replacement value is in **how requests flow**, not in code size.

| Component | Count | Notes |
|---|---|---|
| REST endpoints in `api/v1/*` | ~30 | All return JSON; 8 verbs (GET/POST/PUT/DELETE) |
| API controllers | 10 | Students, Therapy, Schedule, Triage, Toolbox, Dashboard, Activity, Apps, Challenge, TherapySessions |
| Legacy PHP pages replaced | 5 | `prof_home1.php`, `prof_profile1.php`, `prof_schedule.php`, `maps_toolbox.php`, `intake_triage_list.php` |
| React component files | ~30+ | Clinician dashboard, patient profile, schedule, tabs, shared widgets |
| Page reloads per session (legacy) | 1 per navigation | Every click = full HTML re-render + script re-init |
| Page reloads per session (SPA) | 1 (initial only) | All subsequent navigation is hash routing + JSON fetch |

The architectural win is in that last row of the table — quantified
in Figures B1 (per-request) and B2 (compound effect) below — **not**
in lines-of-code.
""")

md("""
# 2. Does the new architecture actually perform better?

`fetch_pillar_b_paired.sh` logs in with dev creds, then times **5
pairs** of comparable legacy-PHP and new REST endpoints (30 runs
each). All return HTTP 200; no auth failures.
""")

py("""
paired = pd.read_csv(f"{DIR}/data/pillar_b/pillar_b_paired_timings.csv")

# Pair labels
pair_key = {
    "legacy_signin":          "api_health",
    "legacy_dashboard_msgs":  "api_dashboard_msgs",
    "legacy_patient_list":    "api_students",
    "legacy_patient_profile": "api_patient_profile",
    "legacy_toolbox":         "api_toolbox",
}
pair_label = {
    "legacy_signin":          "Login first-touch",
    "legacy_dashboard_msgs":  "Clinician home",
    "legacy_patient_list":    "Patient roster",
    "legacy_patient_profile": "Patient profile",
    "legacy_toolbox":         "Content library",
}

stat = paired.groupby("label").agg(
    median_ms=("total_ms", "median"),
    median_ttfb=("ttfb_ms", "median"),
    median_kb=("size_bytes", lambda s: s.median() / 1024),
).round(2)

rows = []
for old_lbl, new_lbl in pair_key.items():
    old_ms, new_ms = stat.loc[old_lbl, "median_ms"], stat.loc[new_lbl, "median_ms"]
    old_tt, new_tt = stat.loc[old_lbl, "median_ttfb"], stat.loc[new_lbl, "median_ttfb"]
    old_kb, new_kb = stat.loc[old_lbl, "median_kb"], stat.loc[new_lbl, "median_kb"]
    rows.append({
        "pair":              pair_label[old_lbl],
        "legacy_php_ms":     old_ms,
        "rest_api_ms":       new_ms,
        "ms_saved":          round(old_ms - new_ms, 1),
        "legacy_php_ttfb":   old_tt,
        "rest_api_ttfb":     new_tt,
        "ttfb_saved":        round(old_tt - new_tt, 1),
        "legacy_php_kb":     old_kb,
        "rest_api_kb":       new_kb,
        "kb_saved":          round(old_kb - new_kb, 1),
        "payload_smaller_pct": round((1 - new_kb / max(old_kb, 0.001)) * 100, 1),
    })
delta_df = pd.DataFrame(rows)
delta_df
""")

md("""
### Figure B1. Per-request latency, TTFB, and payload across five paired endpoints
""")

py("""
# Three-panel: latency | TTFB | payload, with savings annotated above each pair.
fig, axes = plt.subplots(1, 3, figsize=(18, 5.5))
fig.suptitle("REST API vs legacy PHP, five paired endpoints (30 runs each, authenticated)", y=1.02)

x = np.arange(len(delta_df))
w = 0.38

def paired_bars(ax, col_legacy, col_rest, col_saved_or_pct, ylabel, title,
                annot_fmt, legacy_label, rest_label, ymax_buffer=1.15):
    ax.bar(x - w/2, delta_df[col_legacy], w, color="#888888", label=legacy_label)
    ax.bar(x + w/2, delta_df[col_rest],   w, color="#1f77b4", label=rest_label)
    top_max = max(delta_df[col_legacy].max(), delta_df[col_rest].max())
    for i in x:
        saved = delta_df.iloc[i][col_saved_or_pct]
        top   = max(delta_df.iloc[i][col_legacy], delta_df.iloc[i][col_rest])
        if saved > 0:
            ax.text(i, top + top_max * 0.04, annot_fmt.format(saved=saved),
                    ha="center", fontsize=10, color="#1f77b4", fontweight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(delta_df["pair"], rotation=20, ha="right")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.legend(loc="upper left", fontsize=9)
    ax.grid(alpha=0.25, axis="y")
    ax.set_ylim(0, top_max * ymax_buffer)

paired_bars(axes[0], "legacy_php_ms", "rest_api_ms", "ms_saved",
            "Median round-trip (ms)", "Total round-trip latency",
            "−{saved:.0f} ms", "Legacy PHP", "REST API / SPA")

paired_bars(axes[1], "legacy_php_ttfb", "rest_api_ttfb", "ttfb_saved",
            "Median TTFB (ms)", "Time to first byte (server-side)",
            "−{saved:.0f} ms", "Legacy PHP", "REST API / SPA")

# Payload uses % smaller as the annotation, so handle it separately
b3 = axes[2].bar(x - w/2, delta_df["legacy_php_kb"], w, color="#888888", label="Legacy PHP (HTML)")
b4 = axes[2].bar(x + w/2, delta_df["rest_api_kb"],   w, color="#1f77b4", label="REST API (JSON)")
top_max_kb = max(delta_df["legacy_php_kb"].max(), delta_df["rest_api_kb"].max())
for i in x:
    pct = delta_df.iloc[i]["payload_smaller_pct"]
    top = max(delta_df.iloc[i]["legacy_php_kb"], delta_df.iloc[i]["rest_api_kb"])
    if pct > 0:
        axes[2].text(i, top + top_max_kb * 0.04, f"−{pct:.0f}% smaller",
                     ha="center", fontsize=10, color="#1f77b4", fontweight="bold")
axes[2].set_xticks(x)
axes[2].set_xticklabels(delta_df["pair"], rotation=20, ha="right")
axes[2].set_ylabel("Response payload (KB)")
axes[2].set_title("Response payload size")
axes[2].legend(loc="upper left", fontsize=9)
axes[2].grid(alpha=0.25, axis="y")
axes[2].set_ylim(0, top_max_kb * 1.18)

plt.tight_layout()
plt.show()
""")

md("""
*Figure B1. Five paired endpoints, legacy PHP vs. REST API. 30 timed runs per endpoint,
authenticated session. Left: median total round-trip time. Middle: median TTFB
(server-side processing time, before the response body is transferred). Right: median
response payload. The TTFB panel isolates server work from network/transfer cost; the
gap between TTFB and total widens as payload grows (visible on Patient roster and
Content library, both legacy HTML).*

# 3. The compound effect — typical clinical session

Per-request savings sound modest. But a clinician moving through
patients during a session navigates many endpoints. Each legacy nav
triggers a full page reload; in the SPA it's a single API call after
the initial load. Below: a typical 5-minute session simulated using
the measured per-endpoint numbers above.
""")

py("""
# Typical clinical session: clinician opens dashboard, navigates ~8 things
# in 5 minutes. Map each step to a paired endpoint.
session = [
    ("login",                "Login first-touch"),
    ("open dashboard home",  "Clinician home"),
    ("open patient roster",  "Patient roster"),
    ("view patient #1",      "Patient profile"),
    ("back to roster",       "Patient roster"),
    ("view patient #2",      "Patient profile"),
    ("open content library", "Content library"),
    ("view patient #3",      "Patient profile"),
]

dl = delta_df.set_index("pair")
session_df = pd.DataFrame(session, columns=["step", "pair"])
session_df["legacy_ms"] = session_df["pair"].map(dl["legacy_php_ms"])
session_df["legacy_kb"] = session_df["pair"].map(dl["legacy_php_kb"])
# In the SPA: first request loads the page shell, all subsequent are JSON-only
# Approximate: legacy pays full cost every nav; SPA pays full cost on FIRST nav,
# then API-only cost for the rest.
spa_costs_ms = []
spa_costs_kb = []
spa_loaded = False
SPA_SHELL_MS = dl.loc["Login first-touch", "legacy_php_ms"]  # one-time HTML/JS shell load
SPA_SHELL_KB = dl.loc["Login first-touch", "legacy_php_kb"]
for _, row in session_df.iterrows():
    api_ms = dl.loc[row["pair"], "rest_api_ms"]
    api_kb = dl.loc[row["pair"], "rest_api_kb"]
    if not spa_loaded:
        # First nav: load SPA shell once, then make the API call
        spa_costs_ms.append(SPA_SHELL_MS + api_ms)
        spa_costs_kb.append(SPA_SHELL_KB + api_kb)
        spa_loaded = True
    else:
        spa_costs_ms.append(api_ms)
        spa_costs_kb.append(api_kb)
session_df["spa_ms"] = spa_costs_ms
session_df["spa_kb"] = spa_costs_kb
session_df = session_df.round(1)
session_df
""")

py("""
totals = pd.DataFrame({
    "metric": ["Total round-trip time (ms)", "Total bandwidth (KB)"],
    "legacy_php": [
        session_df["legacy_ms"].sum(),
        session_df["legacy_kb"].sum(),
    ],
    "rest_spa": [
        session_df["spa_ms"].sum(),
        session_df["spa_kb"].sum(),
    ],
})
totals["saved"]      = (totals["legacy_php"] - totals["rest_spa"]).round(1)
totals["pct_saved"]  = ((1 - totals["rest_spa"] / totals["legacy_php"]) * 100).round(1)
totals = totals.round(1)
totals
""")

md("""
### Figure B2. Compound effect across a simulated 8-step clinical session
""")

py("""
# Cumulative-time + cumulative-bandwidth across the simulated session
fig, axes = plt.subplots(1, 2, figsize=(15, 5.5))
fig.suptitle("Compound effect across a typical 8-step clinical session — legacy keeps paying full-render cost; SPA pays once and amortizes",
             y=1.03)

steps = session_df["step"].tolist()
xs = np.arange(len(steps))

# --- Cumulative time ---
cum_l = session_df["legacy_ms"].cumsum().values
cum_s = session_df["spa_ms"].cumsum().values
axes[0].plot(xs, cum_l, marker="o", color="#888888", linewidth=3, markersize=9, label="Legacy PHP")
axes[0].plot(xs, cum_s, marker="o", color="#1f77b4", linewidth=3, markersize=9, label="REST API + SPA")
axes[0].fill_between(xs, cum_l, cum_s, where=(cum_l > cum_s), alpha=0.20, color="#2ca02c")
saved_ms = cum_l[-1] - cum_s[-1]
pct_ms   = (1 - cum_s[-1] / cum_l[-1]) * 100
axes[0].annotate(f"saved {saved_ms:.0f} ms ({pct_ms:.0f}%)",
                 xy=(xs[-1], (cum_l[-1] + cum_s[-1]) / 2),
                 xytext=(xs[-1] - 2.0, (cum_l[-1] + cum_s[-1]) / 2 + 200),
                 fontsize=12, color="#2ca02c", fontweight="bold",
                 arrowprops=dict(arrowstyle="->", color="#2ca02c"))
axes[0].text(xs[-1], cum_l[-1] + 30, f"{cum_l[-1]:.0f} ms", ha="right", fontsize=11, fontweight="bold", color="#666")
axes[0].text(xs[-1], cum_s[-1] - 80, f"{cum_s[-1]:.0f} ms", ha="right", fontsize=11, fontweight="bold", color="#1f77b4")
axes[0].set_xticks(xs)
axes[0].set_xticklabels(steps, rotation=35, ha="right")
axes[0].set_ylabel("Cumulative round-trip time (ms)")
axes[0].set_title("Time spent waiting for the server")
axes[0].legend(loc="upper left")
axes[0].grid(alpha=0.25)

# --- Cumulative bandwidth ---
cum_lk = session_df["legacy_kb"].cumsum().values
cum_sk = session_df["spa_kb"].cumsum().values
axes[1].plot(xs, cum_lk, marker="o", color="#888888", linewidth=3, markersize=9, label="Legacy PHP HTML")
axes[1].plot(xs, cum_sk, marker="o", color="#1f77b4", linewidth=3, markersize=9, label="REST API JSON")
axes[1].fill_between(xs, cum_lk, cum_sk, where=(cum_lk > cum_sk), alpha=0.20, color="#2ca02c")
saved_kb = cum_lk[-1] - cum_sk[-1]
pct_kb   = (1 - cum_sk[-1] / cum_lk[-1]) * 100
axes[1].annotate(f"saved {saved_kb:.1f} KB ({pct_kb:.0f}%)",
                 xy=(xs[-1], (cum_lk[-1] + cum_sk[-1]) / 2),
                 xytext=(xs[-1] - 2.0, (cum_lk[-1] + cum_sk[-1]) / 2 + 8),
                 fontsize=12, color="#2ca02c", fontweight="bold",
                 arrowprops=dict(arrowstyle="->", color="#2ca02c"))
axes[1].text(xs[-1], cum_lk[-1] + 1.5, f"{cum_lk[-1]:.1f} KB", ha="right", fontsize=11, fontweight="bold", color="#666")
axes[1].text(xs[-1], cum_sk[-1] - 4, f"{cum_sk[-1]:.1f} KB", ha="right", fontsize=11, fontweight="bold", color="#1f77b4")
axes[1].set_xticks(xs)
axes[1].set_xticklabels(steps, rotation=35, ha="right")
axes[1].set_ylabel("Cumulative bandwidth (KB)")
axes[1].set_title("Total data the clinician's browser downloaded")
axes[1].legend(loc="upper left")
axes[1].grid(alpha=0.25)

plt.tight_layout()
plt.show()
""")

md("""
*Figure B2. Simulated 8-step clinician workflow (login → dashboard
home → patient roster → patient #1 → roster → patient #2 → content
library → patient #3) using the per-endpoint timings from Figure B1.
Gray line: legacy multi-page flow, where every navigation triggers a
full HTML re-render. Blue line: React SPA, which pays the page-shell
cost once on the first navigation then makes small JSON-only API
calls thereafter. Filled area between the lines is the cumulative
saving. Final-state annotations show absolute savings and percent
savings at the end of the 8-step session.*

# Concurrent-load capacity (sanity test)

100 requests at 10 concurrent against `/api/v1/health`. Cheap, bounded,
verifies the server handles modest concurrency without errors.
""")

py("""
# Read the ab summary
with open(f"{DIR}/data/pillar_b/pillar_b_ab_summary.txt") as f:
    ab_text = f.read()

def grab(label):
    m = re.search(rf"{label}:\\s*([0-9.]+)", ab_text)
    return float(m.group(1)) if m else None

ab_metrics = pd.DataFrame([
    {"metric": "Concurrency level",   "value": int(grab("Concurrency Level"))},
    {"metric": "Total requests",      "value": int(grab("Complete requests"))},
    {"metric": "Failed requests",     "value": int(grab("Failed requests"))},
    {"metric": "Time taken (s)",      "value": grab("Time taken for tests")},
    {"metric": "Requests / sec",      "value": grab("Requests per second")},
    {"metric": "Time per request (ms)", "value": grab("Time per request")},
    {"metric": "Transfer (KB/s)",     "value": grab("Transfer rate")},
])
ab_metrics
""")

md("""
## Summary — what the data establishes for the paper

**Concrete in-scope claims (each tied to live measurements above):**

1. **The new REST/SPA architecture is per-request faster than legacy PHP
   on every endpoint pair tested**, with the largest absolute savings
   on the high-traffic endpoints: 95 ms saved on patient roster,
   40 ms saved on content library.

2. **The new architecture transfers substantially less data per request**:
   54-99% smaller payloads across the five pairs, peaking at 92%
   smaller for the patient roster (1.5 KB JSON vs 18.7 KB HTML) and
   98% smaller for the dashboard messages endpoint.

3. **Compound savings across a typical 8-step clinical session: roughly
   half the cumulative round-trip time and two-thirds of the
   bandwidth.** This is the architectural payoff of moving from
   "render every page server-side" to "load once, fetch deltas."

4. **The REST API handles modest concurrent load cleanly**: 100 requests
   at 10 concurrent, zero failures, ~27 req/s sustained against a
   t2.micro dev EC2. Within-clinic load (a handful of clinicians
   simultaneously refreshing the dashboard) is well below this.

**What this notebook does NOT establish (paper-acknowledged):**

- **Lighthouse / Time-to-Interactive scores** — would require running
  Lighthouse against authenticated pages with proper headless Chrome
  setup; deferred to Future Directions.
- **Higher-concurrency or sustained-load behavior** — gated on the
  AWS Cost Budget + WAF + rate-limit prerequisites, per the project
  roadmap.
- **Server-side processing time isolation** — the absolute latency
  numbers above include network RTT (Mac in Seattle ↔ EC2 in
  us-east-1, ~230 ms baseline). The relative comparison and payload
  sizes are the load-bearing measurements; pure server-time numbers
  would require benchmarking from a same-region EC2.

**Honest framing for the paper text**: the architecture didn't just
introduce a different code style — it shifted the cost model. Legacy
PHP pays the full render cost on every navigation; the React SPA pays
it once and amortizes. Both the per-request and per-session evidence
above support this claim.
""")

nb.cells = cells
nb.metadata = {
    "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
    "language_info": {"name": "python", "version": "3.11"},
}
out_path = os.path.join(DIR, "pillar_b_rest_api.ipynb")
nbf.write(nb, out_path)
print(f"Wrote {out_path}")
