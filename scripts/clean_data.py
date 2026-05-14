#!/usr/bin/env python3
"""Stage 2: clean RDS_BO and BlockData CSVs for thesis analysis.

Outputs cleaned CSVs in the same directory with:
  - parsed Note fields (accuracy %, assigned/total time, trials)
  - hashed StudentID (stable across runs via .salt)
  - parsed Date/DateTime
  - normalized Act_Info (trailing-space duplicates collapsed)
  - numeric coercions for vergence, scores, etc.
  - note_format classifier (modern_std / modern_birom / legacy_2019 / unknown)
  - vergence_meaning derived from note_format + Vergence2 presence
  - vergence_outlier boolean flag for |value| > 60 prism diopters

Column-semantics map (recovered from source: APPs/RDS-Vergence/rd3*.php):
  Vergence_peak     = peak achieved value during the session.
                      Direction (BO vs BI) depends on which save handler wrote it:
                        rd3.php       -> peak BO (Convergence/Vertical/M/B variants)
                        rd3_BIROM.php -> peak BI (Divergence Range)
                        rd3_JD.php    -> peak BO (Jump Duction)
                        rd3_blk.php   -> same as rd3.php, MAP-block context
  Vergence2_peak_BI = peak BI achieved, ONLY written by rd3_JD.php (Jump Duction).
  Home              = WHO ran the session, set from $_SESSION['Access']:
                        'P' = Patient/parent (at-home prescribed therapy)
                        'T' = Therapist/clinician (in-clinic supervised)
  RunBy             = same as Home, renamed for readability in the cleaned output.
  BOLimit / BILimit = configured ceilings for the session (the target).
  AssignedTime      = configured session duration (minutes), separate from peak achieved.
  Time              = actual session duration (computed by the canvas timer).

Note-format classifier (used to back-fill which save handler wrote each row,
since RDS_BO has no handler-id column and Pearson's BlockData export has
RecordID stripped):
  modern_std    = "ASSIGNED: X MIN. TOTAL TIME: Y, TRIALS: Z" (rd3, rd3_JD, rd3_blk)
  modern_birom  = "ASSIGNED: X MIN: TOTAL TIME: Y, TRIALS: Z" (rd3_BIROM only)
  legacy_2019   = "TIME: X m, TRIALS: Y, comment" (pre-rd3 era, ~238 rows)
  unknown       = doesn't match any pattern

Re-running with the same .salt produces stable patient hashes.
Original StudentID is dropped from output to limit re-identification risk.
"""
import os
import re
import hashlib
import secrets
import pandas as pd

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)              # parent of scripts/
RAW_DIR = os.path.join(ROOT, "data", "raw")
CLEANED_DIR = os.path.join(ROOT, "data", "cleaned")
SALT_PATH = os.path.join(ROOT, ".salt")
os.makedirs(CLEANED_DIR, exist_ok=True)

# Clinically plausible vergence range. Values outside this are flagged as outliers
# (data-entry errors or test sessions) but kept in the output for transparency.
VERGENCE_OUTLIER_THRESHOLD = 60  # prism diopters, |abs| > this is suspicious

# ---- stable salt for patient hashing ----------------------------------------
if os.path.exists(SALT_PATH):
    with open(SALT_PATH) as f:
        salt = f.read().strip()
else:
    salt = secrets.token_hex(16)
    with open(SALT_PATH, "w") as f:
        f.write(salt)
    os.chmod(SALT_PATH, 0o600)
    print(f"  generated new salt at {SALT_PATH}")

def hash_pid(sid):
    s = "" if pd.isna(sid) else str(sid).strip()
    if s in ("", "0"):
        return ""
    return hashlib.sha256(f"{salt}|{s}".encode()).hexdigest()[:12]

# ---- text cleanup (mojibake + HTML entities) --------------------------------
MOJIBAKE_REPLACEMENTS = [
    ("ÃÂ ", " "),  # double-encoded nbsp seen in latin1-decoded data
    ("Â ", " "),              # single-encoded nbsp
    (" ", " "),                    # raw nbsp
    ("&nbsp;", " "),                    # html entity
]
def clean_text(s):
    if pd.isna(s):
        return ""
    s = str(s)
    for old, new in MOJIBAKE_REPLACEMENTS:
        s = s.replace(old, new)
    return re.sub(r"\s+", " ", s).strip()

# ---- Note field parsing -----------------------------------------------------
ACC_RE      = re.compile(r"(\d+)\s*/\s*(\d+)[^\d|]*?(\d+)\s*%")
ASSIGNED_RE = re.compile(r"ASSIGNED:\s*(\d+)", re.I)
TIME_RE     = re.compile(r"TOTAL\s+TIME:\s*([\d:]+)", re.I)
TIME_OLD_RE = re.compile(r"\bTIME:\s*(\d+)\s*m", re.I)
TRIALS_RE   = re.compile(r"TRIALS:\s*(\d+)", re.I)

# ---- Note-format classifier (recovered from rd3*.php source) ---------------
FMT_BIROM_RE  = re.compile(r"\bMIN\s*:\s*TOTAL", re.I)   # rd3_BIROM.php uses MIN: TOTAL
FMT_STD_RE    = re.compile(r"\bMIN\.\s*TOTAL", re.I)     # rd3.php / rd3_JD.php / rd3_blk.php use MIN. TOTAL
FMT_LEGACY_RE = re.compile(r"^TIME:\s*\d+\s*m", re.I)    # pre-rd3 2019 format

def classify_note_format(text):
    """Return one of: modern_birom, modern_std, legacy_2019, unknown."""
    if not text:
        return "unknown"
    if FMT_BIROM_RE.search(text):
        return "modern_birom"
    if FMT_STD_RE.search(text):
        return "modern_std"
    if FMT_LEGACY_RE.match(text):
        return "legacy_2019"
    return "unknown"

def parse_note(note):
    text = clean_text(note)
    out = {
        "accuracy_correct": pd.NA,
        "accuracy_total":   pd.NA,
        "accuracy_pct":     pd.NA,
        "assigned_min":     pd.NA,
        "total_time":       pd.NA,
        "trials_parsed":    pd.NA,
        "note_format":      classify_note_format(text),
        "note_clean":       text,
    }
    if not text:
        return out
    if (m := ACC_RE.search(text)):
        out["accuracy_correct"] = int(m.group(1))
        out["accuracy_total"]   = int(m.group(2))
        out["accuracy_pct"]     = int(m.group(3))
    if (m := ASSIGNED_RE.search(text)):
        out["assigned_min"] = int(m.group(1))
    if (m := TIME_RE.search(text)) or (m := TIME_OLD_RE.search(text)):
        out["total_time"] = m.group(1)
    if (m := TRIALS_RE.search(text)):
        out["trials_parsed"] = int(m.group(1))
    return out

def vergence_meaning(row):
    """Derive the semantic meaning of the Vergence/Vergence2 columns for a row,
    based on note_format and Vergence2 presence."""
    fmt = row["note_format"]
    has_v2 = pd.notna(row["Vergence2_peak_BI"])
    if fmt == "modern_birom":
        return "Vergence=peak_BI (Divergence Range, rd3_BIROM)"
    if fmt == "modern_std" and has_v2:
        return "Vergence=peak_BO + Vergence2=peak_BI (Jump Duction, rd3_JD)"
    if fmt == "modern_std":
        return "Vergence=peak_BO_or_other (Convergence/Vertical/M/B, rd3 — needs Activity to disambiguate)"
    if fmt == "legacy_2019":
        return "unknown (pre-rd3 era)"
    return "unknown"

# ---- pipeline ---------------------------------------------------------------
def numeric(series):
    return pd.to_numeric(series.replace("", pd.NA), errors="coerce")

def clean_rds_bo():
    print("Loading RDS_BO ...")
    df = pd.read_csv(
        os.path.join(RAW_DIR, "RDS_BO_Joshia_050226.csv"),
        encoding="latin1", dtype=str, keep_default_na=False,
    )
    print(f"  {len(df):,} rows")
    df["StudentHash"]    = df["StudentID"].apply(hash_pid)
    df["DateUnix"]       = numeric(df["Date"])
    df["DateTime"]       = pd.to_datetime(df["DateUnix"], unit="s", errors="coerce")
    df["AssignedTime_n"] = numeric(df["AssignedTime"])
    df["Time_n"]         = numeric(df["Time"])
    df["BOLimit_n"]      = numeric(df["BOLimit"])
    df["BILimit_n"]      = numeric(df["BILimit"])
    df["Vergence_peak"]     = numeric(df["Vergence"])
    df["Vergence2_peak_BI"] = numeric(df["Vergence2"])
    df["Trials_n"]       = numeric(df["Trials"])
    df["RunBy"]          = df["Home"]  # 'P' = Patient/parent (at-home), 'T' = Therapist (in-clinic)
    parsed = df["Note"].apply(parse_note).apply(pd.Series)
    df = pd.concat([df, parsed], axis=1)
    df["vergence_meaning"]   = df.apply(vergence_meaning, axis=1)
    df["vergence_outlier"]   = (df["Vergence_peak"].abs() > VERGENCE_OUTLIER_THRESHOLD).fillna(False)
    df["vergence2_outlier"]  = (df["Vergence2_peak_BI"].abs() > VERGENCE_OUTLIER_THRESHOLD).fillna(False)
    df = df.drop(columns=["StudentID"])
    out = os.path.join(CLEANED_DIR, "RDS_BO_cleaned.csv")
    df.to_csv(out, index=False)
    print(f"  -> {out}")
    return df

def clean_block_data():
    print("Loading BlockData ...")
    df = pd.read_csv(
        os.path.join(RAW_DIR, "BlockDataForRDS_Josiah_050226.csv"),
        encoding="latin1", dtype=str, keep_default_na=False,
    )
    print(f"  {len(df):,} rows")
    df["StudentHash"] = df["StudentID"].apply(hash_pid)
    df["DateUnix"]    = numeric(df["Date"])
    df["DateTime"]    = pd.to_datetime(df["DateUnix"], unit="s", errors="coerce")
    df["Activity"]    = df["Act_Info"].str.strip()  # collapse trailing-space duplicates
    df["RunBy"]       = df["Home"]  # same P/T meaning as RDS_BO
    df["BlockID_n"]   = numeric(df["BlockID"])
    df["SCORE1_n"]    = numeric(df["SCORE1"])
    df["SCORE2_n"]    = numeric(df["SCORE2"])
    df["SCORE3_n"]    = numeric(df["SCORE3"])
    df["SCORE4_n"]    = numeric(df["SCORE4"])
    parsed = df["Note"].apply(parse_note).apply(pd.Series)
    df = pd.concat([df, parsed], axis=1)
    df = df.drop(columns=["StudentID", "ActivityName"])  # ActivityName is empty everywhere
    out = os.path.join(CLEANED_DIR, "BlockData_cleaned.csv")
    df.to_csv(out, index=False)
    print(f"  -> {out}")
    return df

def report(rds, blk):
    print("\n=== Note-parse coverage ===")
    for label, df in [("RDS_BO", rds), ("BlockData", blk)]:
        print(f"  {label}:")
        for col in ["accuracy_pct", "assigned_min", "total_time", "trials_parsed"]:
            n = df[col].notna().sum()
            print(f"    {col:<16} {n:>6,} / {len(df):,} ({n/len(df)*100:5.1f}%)")

    print("\n=== Note-format classification ===")
    for label, df in [("RDS_BO", rds), ("BlockData", blk)]:
        print(f"  {label}:")
        for fmt, n in df["note_format"].value_counts().items():
            print(f"    {fmt:<16} {n:>6,} ({n/len(df)*100:5.1f}%)")

    print("\n=== RDS_BO vergence_meaning breakdown ===")
    for meaning, n in rds["vergence_meaning"].value_counts().items():
        print(f"  {n:>6,}  {meaning}")

    print("\n=== Outlier flags (|value| > {} PD) ===".format(VERGENCE_OUTLIER_THRESHOLD))
    print(f"  Vergence_peak    outliers: {rds['vergence_outlier'].sum():,}")
    print(f"  Vergence2_peak_BI outliers: {rds['vergence2_outlier'].sum():,}")

    print("\n=== Patient hashing ===")
    rds_pids = rds.loc[rds['StudentHash'] != '', 'StudentHash'].nunique()
    blk_pids = blk.loc[blk['StudentHash'] != '', 'StudentHash'].nunique()
    print(f"  RDS_BO    distinct patients: {rds_pids}")
    print(f"  BlockData distinct patients: {blk_pids}")

    print("\n=== RunBy distribution ===")
    for label, df in [("RDS_BO", rds), ("BlockData", blk)]:
        print(f"  {label}:")
        for v, n in df["RunBy"].value_counts().items():
            who = {"P": "Patient/parent (at-home)", "T": "Therapist (in-clinic)"}.get(v, "?")
            print(f"    {v}: {n:>6,}  ({who})")

if __name__ == "__main__":
    rds = clean_rds_bo()
    blk = clean_block_data()
    report(rds, blk)
    print("\nDone.")
