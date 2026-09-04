#!/usr/bin/env bash
set -euo pipefail

# Experiment 3: Benchmark object-key decoding across LuaJIT and PUC Lua 5.2–5.5
# Outputs structured METRIC lines for autoresearch.

cd "$(dirname "$0")/.."

if [ "${1:-}" = "--update-baseline" ]; then
    if [ ! -f "autoresearch/latest_run.json" ]; then
        echo "ERROR: autoresearch/latest_run.json not found. Run benchmark first." >&2
        exit 1
    fi

    python3 - <<'PY'
import json

latest_path = "autoresearch/latest_run.json"
baseline_path = "autoresearch/baseline_metrics.json"
with open(latest_path, encoding="utf-8") as handle:
    latest = json.load(handle)

if latest.get("veto") or latest.get("composite_decode_ms", 99999.0) >= 99999.0:
    raise SystemExit("ERROR: refusing to promote a vetoed benchmark run")

keys = [
    "luajit_decode_ms", "lua52_decode_ms", "lua53_decode_ms",
    "lua54_decode_ms", "lua55_decode_ms",
]
if any(not isinstance(latest.get(key), (int, float)) or latest[key] <= 0 for key in keys):
    raise SystemExit("ERROR: latest benchmark has incomplete decode metrics")

baseline = {key: latest[key] for key in keys}
with open(baseline_path, "w", encoding="utf-8") as handle:
    json.dump(baseline, handle, indent=2)
    handle.write("\n")
print(f"Successfully updated {baseline_path}")
PY
    exit 0
fi

export BENCH_SETS="${BENCH_SETS:-5}"
export BENCH_MIN_ITERS="${BENCH_MIN_ITERS:-3}"
export BENCH_WARMUP="${BENCH_WARMUP:-5}"

get_runtime_cmd() {
    local env_name="$1"
    case "$env_name" in
        luajit)
            local p="/nix/store/pjfimqddvyxb9d737wv4jplx4a6rdvqn-luajit-2.1.1741730670-env/bin/luajit"
            if [ -x "$p" ]; then echo "$p"; return; fi
            ;;
        lua52)
            local p="/nix/store/5qwjazbwn1v2vi91ah83lv6gqv6kggd8-lua-5.2.4-env/bin/lua"
            if [ -x "$p" ]; then echo "$p"; return; fi
            ;;
        lua53)
            local p="/nix/store/66rilm6nh7maszlff1230y272gf5bhm1-lua-5.3.6-env/bin/lua"
            if [ -x "$p" ]; then echo "$p"; return; fi
            ;;
        lua54)
            local p="/nix/store/i7fg11dggvnlz2fb074z0q2gmcyvz0al-lua-5.4.7-env/bin/lua"
            if [ -x "$p" ]; then echo "$p"; return; fi
            ;;
        lua55)
            local p="/nix/store/h51cwfaram1vvzwrkvd68ybv9pcs94fi-lua-5.5.0-env/bin/lua"
            if [ -x "$p" ]; then echo "$p"; return; fi
            ;;
    esac
    echo ""
}

# Step 1: Pre-check library loading across all 5 environments
for env in luajit lua52 lua53 lua54 lua55; do
    rcmd=$(get_runtime_cmd "$env")
    if [ -n "$rcmd" ]; then
        if ! env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" "$rcmd" -e "require('wjson')" 2>/dev/null; then
            echo "ERROR: wjson failed to load in $env"
            exit 1
        fi
    else
        bin="lua"
        if [ "$env" = "luajit" ]; then bin="luajit"; fi
        if ! nix develop .#"$env" -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" "$bin" -e "require('wjson')" 2>/dev/null; then
            echo "ERROR: wjson failed to load in $env"
            exit 1
        fi
    fi
done

# Step 2: Run the full test suite (must pass across all 5 engines)
echo "Running test suite across all 5 environments..."
if ! ./run_tests.sh > /dev/null 2>&1; then
    echo "ERROR: test suite failed on one or more environments"
    exit 1
fi

# Step 3: Helper function to parse benchmark output
parse_metrics() {
    local output="$1"
    echo "$output" | awk '
    /Encode:[[:space:]]+[0-9.]+[[:space:]]+ms.*Decode:[[:space:]]+[0-9.]+[[:space:]]+ms/ {
        for (i=1; i<=NF; i++) {
            if ($i == "Encode:") ev = $(i+1)
            if ($i == "Decode:") dv = $(i+1)
        }
        es += ev
        ds += dv
        if ($0 ~ /synthetic-complex-numbers/) {
            nd = dv
        }
    }
    END {
        printf "%.2f %.2f %.2f\n", (es ? es : 0), (ds ? ds : 0), (nd ? nd : 0)
    }'
}

# Step 4: Benchmark each runtime repeatedly and use the median sample.
# A single cold LuaJIT decode is dominated by trace compilation and is not a
# trustworthy throughput measurement.
BENCH_REPEATS="${BENCH_REPEATS:-3}"
if ! [[ "$BENCH_REPEATS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: BENCH_REPEATS must be a positive integer" >&2
    exit 1
fi

run_runtime() {
    local env_name="$1"
    local bin="lua"
    if [ "$env_name" = "luajit" ]; then bin="luajit"; fi

    local -a encode_values=()
    local -a decode_values=()
    local -a number_values=()

    for repeat in $(seq 1 "$BENCH_REPEATS"); do
        echo "Benchmarking $env_name (repeat $repeat/$BENCH_REPEATS)..." >&2
        local output
        local rcmd
        rcmd=$(get_runtime_cmd "$env_name")
        if [ -n "$rcmd" ]; then
            output=$(env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" "$rcmd" bench/bench.lua 2>&1)
        else
            output=$(nix develop .#"$env_name" -c env \
                LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" \
                "$bin" bench/bench.lua 2>&1)
        fi
        read -r encode decode numbers <<< "$(parse_metrics "$output")"
        encode_values+=("$encode")
        decode_values+=("$decode")
        number_values+=("$numbers")
    done

    python3 - "$env_name" "${encode_values[@]}" -- "${decode_values[@]}" -- "${number_values[@]}" <<'PY'
import statistics
import sys

name = sys.argv[1]
first = 2
separator = sys.argv.index("--", first)
encodes = [float(value) for value in sys.argv[first:separator]]
second = separator + 1
separator = sys.argv.index("--", second)
decodes = [float(value) for value in sys.argv[second:separator]]
numbers = [float(value) for value in sys.argv[separator + 1:]]

print(f"{statistics.median(encodes):.2f}",
      f"{statistics.median(decodes):.2f}",
      f"{statistics.median(numbers):.2f}")
PY
}

read -r luajit_encode luajit_decode luajit_numbers <<< "$(run_runtime luajit)"
luajit_total=$(echo "$luajit_encode + $luajit_decode" | bc -l)

for env in lua52 lua53 lua54 lua55; do
    read -r e_val d_val n_val <<< "$(run_runtime "$env")"
    tot=$(echo "$e_val + $d_val" | bc -l)

    case "$env" in
        lua52) lua52_encode=$e_val; lua52_decode=$d_val; lua52_numbers=$n_val; lua52_total=$tot ;;
        lua53) lua53_encode=$e_val; lua53_decode=$d_val; lua53_numbers=$n_val; lua53_total=$tot ;;
        lua54) lua54_encode=$e_val; lua54_decode=$d_val; lua54_numbers=$n_val; lua54_total=$tot ;;
        lua55) lua55_encode=$e_val; lua55_decode=$d_val; lua55_numbers=$n_val; lua55_total=$tot ;;
    esac
done

# Step 6: Evaluate Design A (Penalized Geomean Latency)
python3 - << 'EOF' "$luajit_decode" "$lua52_decode" "$lua53_decode" "$lua54_decode" "$lua55_decode" \
             "$luajit_encode" "$lua52_encode" "$lua53_encode" "$lua54_encode" "$lua55_encode" \
             "$luajit_numbers" "$lua52_numbers" "$lua53_numbers" "$lua54_numbers" "$lua55_numbers" \
             "$luajit_total" "$lua52_total" "$lua53_total" "$lua54_total" "$lua55_total"
import sys, json, os, math

(lj_d, l52_d, l53_d, l54_d, l55_d,
 lj_e, l52_e, l53_e, l54_e, l55_e,
 lj_n, l52_n, l53_n, l54_n, l55_n,
 lj_t, l52_t, l53_t, l54_t, l55_t) = [float(x) for x in sys.argv[1:21]]

current_metrics = {
    "luajit_decode_ms": lj_d,
    "lua52_decode_ms": l52_d,
    "lua53_decode_ms": l53_d,
    "lua54_decode_ms": l54_d,
    "lua55_decode_ms": l55_d,
    "luajit_numbers_ms": lj_n,
    "lua52_numbers_ms": l52_n,
    "lua53_numbers_ms": l53_n,
    "lua54_numbers_ms": l54_n,
    "lua55_numbers_ms": l55_n,
    "luajit_total_ms": lj_t,
    "lua52_total_ms": l52_t,
    "lua53_total_ms": l53_t,
    "lua54_total_ms": l54_t,
    "lua55_total_ms": l55_t,
}

# Keep the measurement artifact separate from the versioned baseline.
os.makedirs("autoresearch", exist_ok=True)

# Geometric mean of decode times across all 5 runtimes
decode_times = [lj_d, l52_d, l53_d, l54_d, l55_d]
log_sum = sum(math.log(t) for t in decode_times if t > 0)
geomean_decode = math.exp(log_sum / len(decode_times))

baseline_file = "autoresearch/baseline_metrics.json"
noise_threshold = float(os.environ.get("NOISE_THRESHOLD", "0.02"))  # 2.0% noise tolerance

veto = False
veto_reasons = []

if os.path.exists(baseline_file) and os.path.getsize(baseline_file) > 0:
    try:
        with open(baseline_file, "r") as f:
            baseline = json.load(f)
        
        decode_keys = [
            "luajit_decode_ms",
            "lua52_decode_ms",
            "lua53_decode_ms",
            "lua54_decode_ms",
            "lua55_decode_ms",
        ]
        
        for k in decode_keys:
            base_val = baseline.get(k)
            curr_val = current_metrics.get(k)
            if base_val and curr_val:
                delta_ratio = (curr_val - base_val) / base_val
                pct = delta_ratio * 100
                if delta_ratio > noise_threshold:
                    veto = True
                    veto_reasons.append(f"{k} regressed by {pct:+.2f}% ({curr_val:.2f}ms vs baseline {base_val:.2f}ms, limit +{noise_threshold*100:.1f}%)")
    except Exception as e:
        print(f"Warning: Failed reading baseline file {baseline_file}: {e}", file=sys.stderr)
else:
    # First baseline run: initialize baseline_metrics.json
    with open(baseline_file, "w") as f:
        json.dump(current_metrics, f, indent=2)
    print(f"[BASELINE] Initialized {baseline_file}")

# Output evaluation result
if veto:
    composite_ms = 99999.00
    print("\n=========================================================================")
    print("AUTORESEARCH DUAL-GATE EVALUATION: VETO (REGRESSION DETECTED)")
    for reason in veto_reasons:
        print(f"  ❌ [VETO] {reason}")
    print(f"  Raw Geomean: {geomean_decode:.2f}ms -> Penalized: {composite_ms:.2f}ms")
    print("=========================================================================\n")
else:
    composite_ms = geomean_decode
    print("\n=========================================================================")
    print("AUTORESEARCH DUAL-GATE EVALUATION: PASS")
    print(f"  ✅ All 5 runtimes within noise tolerance (+{noise_threshold*100:.1f}%) or improved")
    print(f"  Geomean decode: {composite_ms:.2f} ms")
    print("=========================================================================\n")

latest_payload = dict(current_metrics)
latest_payload["composite_decode_ms"] = composite_ms
latest_payload["veto"] = veto
with open("autoresearch/latest_run.json", "w", encoding="utf-8") as f:
    json.dump(latest_payload, f, indent=2)
    f.write("\n")


# Primary composite metric (lower is better)
print(f"METRIC composite_decode_ms={composite_ms:.2f}")

# Granular metrics for independent tracking
for k, v in current_metrics.items():
    print(f"METRIC {k}={v:.2f}")
EOF

