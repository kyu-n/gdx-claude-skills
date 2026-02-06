#!/usr/bin/env bash
set -euo pipefail

# ── libGDX Skills Test Harness (Claude Code CLI) ───────────────────────────
# Runs test prompts with/without skills via `claude -p`, 3x per arm.
# Individual runs graded by sonnet; final verdict adjudicated by Opus 4.6.
#
# Usage:
#   ./run_tests.sh                     # full run, 3 runs/arm, 4 parallel tests
#   ./run_tests.sh --skills-only       # skip baseline arm
#   ./run_tests.sh --runs 5            # 5 runs per arm (more signal, more cost)
#   ./run_tests.sh --jobs 8            # 8 parallel tests
#   ./run_tests.sh --ids lwjgl3-01     # specific tests only
#   ./run_tests.sh --model haiku       # change test subject model (adjudicator stays opus)
#
# Per-test cost: (RUNS × 2 + 1) × active_arms  claude calls
# Default (3 runs, both arms): 14 calls/test, ~700 total for 50 tests
#
# Requires: claude (Claude Code CLI), jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/skills"
PROMPTS_FILE="$SCRIPT_DIR/test_prompts.json"
RESULTS_DIR="$SCRIPT_DIR/results"
REPORT_FILE="$SCRIPT_DIR/report.md"
TMP_DIR="$SCRIPT_DIR/.tmp"

# Constants
SKIPPED_ADJ='{"pass": null, "confidence": "high", "classification": "clear_pass", "run_verdicts": [], "reason": "skipped"}'

# Defaults
MODEL="sonnet"
ADJUDICATOR_MODEL="opus"
JOBS=4
RUNS=3
RUN_BASELINE=true
RUN_SKILLS=true
FILTER_IDS=""

# ── Parse args ──────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)         MODEL="$2"; shift 2 ;;
        --adjudicator)   ADJUDICATOR_MODEL="$2"; shift 2 ;;
        --jobs)          JOBS="$2"; shift 2 ;;
        --runs)          RUNS="$2"; shift 2 ;;
        --skills-only)   RUN_BASELINE=false; shift ;;
        --baseline-only) RUN_SKILLS=false; shift ;;
        --ids)           FILTER_IDS="$2"; shift 2 ;;
        --help)
            cat <<USAGE
Usage: $0 [OPTIONS]
  --model MODEL       Test subject model (default: sonnet)
  --adjudicator MODEL Adjudicator model (default: opus)
  --jobs N            Parallel tests (default: 4)
  --runs N            Runs per arm (default: 3)
  --skills-only       Skip baseline arm
  --baseline-only     Skip skills arm
  --ids id1,id2       Run specific tests only
USAGE
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Preflight ───────────────────────────────────────────────────────────────

if ! command -v claude &>/dev/null; then
    echo "ERROR: 'claude' CLI not found. Install Claude Code: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: 'jq' not found. Install: sudo dnf install jq"
    exit 1
fi

[[ -f "$PROMPTS_FILE" ]] || { echo "ERROR: $PROMPTS_FILE not found"; exit 1; }
[[ -d "$SKILLS_DIR" ]] || { echo "ERROR: $SKILLS_DIR not found"; exit 1; }

mkdir -p "$RESULTS_DIR" "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── Build system prompt files ───────────────────────────────────────────────

BASELINE_PROMPT_FILE="$TMP_DIR/baseline_system.txt"
SKILLS_PROMPT_FILE="$TMP_DIR/skills_system.txt"
GRADER_PROMPT_FILE="$TMP_DIR/grader_system.txt"
ADJUDICATOR_PROMPT_FILE="$TMP_DIR/adjudicator_system.txt"

cat > "$BASELINE_PROMPT_FILE" <<'EOF'
You are an expert libGDX game development assistant. Provide accurate, up-to-date code and advice.
EOF

{
    cat <<'HEADER'
You are an expert libGDX game development assistant. Provide accurate, up-to-date code and advice.

Use the following reference documentation to ensure accuracy:

<libgdx_skills>
HEADER

    while IFS= read -r md; do
        name="$(basename "$(dirname "$md")")"
        printf '<skill name="%s">\n' "$name"
        cat "$md"
        printf '\n</skill>\n\n'
    done < <(find "$SKILLS_DIR" -name "SKILL.md" | sort)

    cat <<'FOOTER'
</libgdx_skills>

When answering questions, always check these skills for the correct APIs, patterns, and common pitfalls. Follow the guidance in the skills over your training data if they conflict.
FOOTER
} > "$SKILLS_PROMPT_FILE"

cat > "$GRADER_PROMPT_FILE" <<'EOF'
You are a strict test grader. Output only valid JSON, no markdown fences, no commentary.
EOF

cat > "$ADJUDICATOR_PROMPT_FILE" <<'EOF'
You are a senior evaluation adjudicator for an LLM skills test harness. Your job is to review
multiple runs of the same test and produce a final verdict that filters out sampling noise.

You will receive:
- The test criteria and prompt
- Multiple response/grade pairs from independent runs
- The individual grader verdicts

Your task is to determine whether the underlying MODEL BEHAVIOR (not any single run) passes or fails.

Think carefully about:
1. If 3/3 runs agree, that's clear signal. Report it.
2. If 2/3 agree, check whether the dissenting run failed for a substantive reason or a superficial one.
   - Substantive: wrong API, incorrect information, missing critical content
   - Superficial: formatting choice, asked clarifying questions instead of coding, minor omission
3. If 1/3 or 0/3 pass, this is likely a real failure — but check if the grader was too strict.
4. Check whether the grader misapplied criteria (e.g., penalizing mention of an anti-pattern
   when the response was warning AGAINST the anti-pattern).

Output EXACTLY this JSON (no markdown fences):
{
  "pass": true or false,
  "confidence": "high" or "medium" or "low",
  "classification": "clear_pass" or "clear_fail" or "noise" or "edge_case" or "grader_error",
  "run_verdicts": [true, false, true],
  "reason": "2-3 sentence explanation of your decision and what you observed across runs"
}

Definitions:
- clear_pass: All or nearly all runs pass for substantive reasons
- clear_fail: All or nearly all runs fail for the same substantive reason
- noise: Runs disagree due to sampling variation, not a real skill issue
- edge_case: The test criteria are ambiguous or the boundary between pass/fail is genuinely unclear
- grader_error: The individual grader misapplied the criteria; your verdict corrects it
EOF

echo "Skills prompt: $(wc -c < "$SKILLS_PROMPT_FILE") bytes"
echo "Adjudicator: $ADJUDICATOR_MODEL"

# ── Helpers ─────────────────────────────────────────────────────────────────

get_test_ids() {
    if [[ -n "$FILTER_IDS" ]]; then
        echo "$FILTER_IDS" | tr ',' '\n'
    else
        jq -r '.[].id' "$PROMPTS_FILE"
    fi
}

get_test_field() {
    local test_id="$1" field="$2"
    jq -r --arg id "$test_id" '.[] | select(.id == $id) | .'"$field" "$PROMPTS_FILE"
}

# ── Extract JSON from potentially messy LLM output ─────────────────────────
# Usage: extract_json [--fallback grade] FILE
#   --fallback grade: if all JSON parsing fails, infer pass/fail from prose

extract_json() {
    local fallback=""
    if [[ "${1:-}" == "--fallback" ]]; then
        fallback="$2"; shift 2
    fi
    local file="$1"
    local cleaned
    cleaned="$(grep -v '^ *```' "$file" | grep -v '^$')"

    # Try whole cleaned output as JSON
    if echo "$cleaned" | jq -e '.' &>/dev/null; then
        echo "$cleaned"
        return
    fi

    # Bracket-matching extraction via python3 (handles nested JSON)
    local extracted
    extracted="$(python3 -c "
import json, sys
text = open(sys.argv[1]).read()
best = None
for i in range(len(text) - 1, -1, -1):
    if text[i] == '{':
        try:
            obj = json.loads(text[i:])
            if 'pass' in obj:
                best = obj
                break
        except json.JSONDecodeError:
            depth = 0
            for j in range(i, len(text)):
                if text[j] == '{': depth += 1
                elif text[j] == '}': depth -= 1
                if depth == 0:
                    try:
                        obj = json.loads(text[i:j+1])
                        if 'pass' in obj:
                            best = obj
                            break
                    except json.JSONDecodeError:
                        pass
                    break
if best:
    print(json.dumps(best))
else:
    sys.exit(1)
" "$file" 2>/dev/null)"

    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e '.' &>/dev/null; then
        echo "$extracted"
        return
    fi

    # Fallback: infer pass/fail from prose (grade-only)
    if [[ "$fallback" == "grade" ]]; then
        local text
        text="$(cat "$file")"
        if echo "$text" | grep -qi '"pass":\s*true\|PASS\b\|passes\b\|correctly'; then
            jq -n --arg reason "inferred pass from prose: ${text:0:200}" '{"pass": true, "reason": $reason}'
        elif echo "$text" | grep -qi '"pass":\s*false\|FAIL\b\|fails\b\|violates\|incorrect'; then
            jq -n --arg reason "inferred fail from prose: ${text:0:200}" '{"pass": false, "reason": $reason}'
        else
            echo '{"pass": null, "reason": "grade parse error"}'
        fi
        return
    fi

    echo '{"pass": null, "confidence": "low", "classification": "grader_error", "run_verdicts": [], "reason": "adjudication parse error"}'
}

parse_adj_fields() {
    local json="$1" prefix="$2"
    eval "${prefix}_pass=\"\$(echo \"\$json\" | jq -r 'if .pass == null then \"null\" else (.pass | tostring) end' 2>/dev/null || echo \"null\")\""
    eval "${prefix}_conf=\"\$(echo \"\$json\" | jq -r '.confidence // \"low\"' 2>/dev/null || echo \"low\")\""
    eval "${prefix}_class=\"\$(echo \"\$json\" | jq -r '.classification // \"grader_error\"' 2>/dev/null || echo \"grader_error\")\""
    eval "${prefix}_reason=\"\$(echo \"\$json\" | jq -r '.reason // \"parse error\"' 2>/dev/null || echo \"parse error\")\""
    eval "${prefix}_runs=\"\$(echo \"\$json\" | jq -c '.run_verdicts // []' 2>/dev/null || echo \"[]\")\""
}

# ── Run single response ────────────────────────────────────────────────────

run_one() {
    local system_file="$1" prompt="$2" output_file="$3"
    echo "$prompt" | claude -p \
        --system-prompt-file "$system_file" \
        --model "$MODEL" \
        --output-format text \
        --disable-slash-commands \
        > "$output_file" 2>/dev/null || true
}

# ── Grade single response ──────────────────────────────────────────────────

grade_one() {
    local test_id="$1" arm_label="$2" response_file="$3" grade_file="$4"

    local criteria must_contain must_not_contain prompt response
    criteria="$(get_test_field "$test_id" "criteria")"
    must_contain="$(get_test_field "$test_id" "must_contain")"
    must_not_contain="$(get_test_field "$test_id" "must_not_contain")"
    prompt="$(get_test_field "$test_id" "prompt")"
    response="$(head -n 200 "$response_file")"

    local grade_prompt_file="$TMP_DIR/grade_${test_id}_${arm_label// /_}_$$.txt"
    cat > "$grade_prompt_file" <<GRADEEOF
You are grading an LLM response for correctness about libGDX game development.

TEST ID: ${test_id}
USER PROMPT: ${prompt}
GRADING CRITERIA: ${criteria}

KEYWORDS THAT MUST APPEAR (at least one form/synonym): ${must_contain}
KEYWORDS THAT MUST NOT APPEAR: ${must_not_contain}

RESPONSE TO GRADE (${arm_label}):
---
${response}
---

Grade this response. Output EXACTLY this JSON format, nothing else:
{"pass": true, "reason": "1-2 sentence explanation"}
or
{"pass": false, "reason": "1-2 sentence explanation"}

Rules:
- must_contain keywords: check for semantic presence, not exact string match.
- must_not_contain: anti-patterns. If the response includes them (even in code), it FAILS unless explicitly warning AGAINST using them.
- Apply the criteria holistically. A response can fail on criteria even if keyword checks pass.
- Be strict: partial credit is a FAIL.
GRADEEOF

    claude -p \
        --system-prompt-file "$GRADER_PROMPT_FILE" \
        --model "$MODEL" \
        --output-format text \
        --disable-slash-commands \
        < "$grade_prompt_file" \
        > "$grade_file" 2>/dev/null || echo '{"pass": false, "reason": "grading call failed"}' > "$grade_file"

    rm -f "$grade_prompt_file"
}

# ── Adjudicate N runs with Opus ─────────────────────────────────────────────

adjudicate_arm() {
    local test_id="$1" arm_label="$2" arm_dir="$3" adjudication_file="$4"

    local criteria must_contain must_not_contain prompt
    criteria="$(get_test_field "$test_id" "criteria")"
    must_contain="$(get_test_field "$test_id" "must_contain")"
    must_not_contain="$(get_test_field "$test_id" "must_not_contain")"
    prompt="$(get_test_field "$test_id" "prompt")"

    # Build the evidence block
    local evidence=""
    local run_idx
    for run_idx in $(seq 1 "$RUNS"); do
        local resp_file="$arm_dir/run${run_idx}_response.txt"
        local grade_file="$arm_dir/run${run_idx}_grade.json"

        local resp_excerpt grade_json grade_pass grade_reason
        resp_excerpt="$(head -n 100 "$resp_file" 2>/dev/null || echo "(empty)")"
        grade_json="$(extract_json --fallback grade "$grade_file")"
        grade_pass="$(echo "$grade_json" | jq -r 'if .pass == null then "null" else (.pass | tostring) end' 2>/dev/null || echo "null")"
        grade_reason="$(echo "$grade_json" | jq -r 'if .reason == null then "parse error" else .reason end' 2>/dev/null || echo "parse error")"

        evidence+="
<run number=\"${run_idx}\">
<response>
${resp_excerpt}
</response>
<grade pass=\"${grade_pass}\">
${grade_reason}
</grade>
</run>
"
    done

    local adj_prompt_file="$TMP_DIR/adj_${test_id}_${arm_label// /_}_$$.txt"
    cat > "$adj_prompt_file" <<ADJEOF
Review these ${RUNS} independent runs of a libGDX skills test.

<test>
<id>${test_id}</id>
<arm>${arm_label}</arm>
<prompt>${prompt}</prompt>
<criteria>${criteria}</criteria>
<must_contain>${must_contain}</must_contain>
<must_not_contain>${must_not_contain}</must_not_contain>
</test>

<runs>
${evidence}
</runs>

Produce your final adjudication as JSON.
ADJEOF

    claude -p \
        --system-prompt-file "$ADJUDICATOR_PROMPT_FILE" \
        --model "$ADJUDICATOR_MODEL" \
        --output-format text \
        --disable-slash-commands \
        < "$adj_prompt_file" \
        > "$adjudication_file" 2>/dev/null || echo '{"pass": false, "confidence": "low", "classification": "grader_error", "run_verdicts": [], "reason": "adjudication call failed"}' > "$adjudication_file"

    rm -f "$adj_prompt_file"
}

# ── Run one arm (N runs + grades + adjudication) ───────────────────────────

run_arm_full() {
    local test_id="$1" arm_label="$2" system_file="$3" arm_dir="$4"

    local prompt
    prompt="$(get_test_field "$test_id" "prompt")"

    mkdir -p "$arm_dir"

    # Run N times and grade each
    local run_idx
    for run_idx in $(seq 1 "$RUNS"); do
        run_one "$system_file" "$prompt" "$arm_dir/run${run_idx}_response.txt"
        grade_one "$test_id" "$arm_label" "$arm_dir/run${run_idx}_response.txt" "$arm_dir/run${run_idx}_grade.json"
    done

    # Adjudicate
    adjudicate_arm "$test_id" "$arm_label" "$arm_dir" "$arm_dir/adjudication.json"
}

# ── Run one complete test ───────────────────────────────────────────────────

run_test() {
    local test_id="$1"
    local test_dir="$RESULTS_DIR/$test_id"
    mkdir -p "$test_dir"

    local skill
    skill="$(get_test_field "$test_id" "skill")"

    # Baseline arm
    if [[ "$RUN_BASELINE" == "true" ]]; then
        run_arm_full "$test_id" "baseline" "$BASELINE_PROMPT_FILE" "$test_dir/baseline"
    else
        mkdir -p "$test_dir/baseline"
        echo "$SKIPPED_ADJ" > "$test_dir/baseline/adjudication.json"
    fi

    # Skills arm
    if [[ "$RUN_SKILLS" == "true" ]]; then
        run_arm_full "$test_id" "skills" "$SKILLS_PROMPT_FILE" "$test_dir/skills"
    else
        mkdir -p "$test_dir/skills"
        echo "$SKIPPED_ADJ" > "$test_dir/skills/adjudication.json"
    fi

    # Parse adjudications
    local b_adj s_adj
    b_adj="$(extract_json "$test_dir/baseline/adjudication.json")"
    s_adj="$(extract_json "$test_dir/skills/adjudication.json")"

    local b_pass b_conf b_class b_reason b_runs
    parse_adj_fields "$b_adj" "b"

    local s_pass s_conf s_class s_reason s_runs
    parse_adj_fields "$s_adj" "s"

    # Write result
    jq -n --arg id "$test_id" --arg skill "$skill" \
        --arg bp "$b_pass" --arg bc "$b_conf" --arg bk "$b_class" --arg br "$b_reason" --argjson bv "$b_runs" \
        --arg sp "$s_pass" --arg sc "$s_conf" --arg sk "$s_class" --arg sr "$s_reason" --argjson sv "$s_runs" \
        '{id: $id, skill: $skill,
          baseline_pass: ($bp | if . == "true" then true elif . == "false" then false else null end),
          baseline_confidence: $bc, baseline_classification: $bk,
          baseline_run_verdicts: $bv, baseline_reason: $br,
          skills_pass: ($sp | if . == "true" then true elif . == "false" then false else null end),
          skills_confidence: $sc, skills_classification: $sk,
          skills_run_verdicts: $sv, skills_reason: $sr}' \
        > "$test_dir/result.json"

    # Progress — show run verdicts inline
    local b_icon s_icon
    case "$b_pass" in
        true) b_icon="✅" ;; false) b_icon="❌" ;; *) b_icon="⏭️" ;;
    esac
    case "$s_pass" in
        true) s_icon="✅" ;; false) s_icon="❌" ;; *) s_icon="⏭️" ;;
    esac

    local b_runs_str s_runs_str
    b_runs_str="$(echo "$b_runs" | jq -r '[.[] | if . == true then "✓" elif . == false then "✗" else "?" end] | join("")')"
    s_runs_str="$(echo "$s_runs" | jq -r '[.[] | if . == true then "✓" elif . == false then "✗" else "?" end] | join("")')"

    printf "  %-20s base=%s[%s]%-6s  skills=%s[%s]%-6s  %s/%s\n" \
        "$test_id" "$b_icon" "$b_runs_str" "($b_conf)" \
        "$s_icon" "$s_runs_str" "($s_conf)" "$b_class" "$s_class"
}

# ── Generate report ─────────────────────────────────────────────────────────

generate_report() {
    local all_results="$RESULTS_DIR/all_results.json"
    find "$RESULTS_DIR" -name "result.json" -print0 | sort -z | xargs -0 jq -s '.' > "$all_results"

    local total base_pass base_fail skill_pass skill_fail
    total="$(jq 'length' "$all_results")"
    base_pass="$(jq '[.[] | select(.baseline_pass == true)] | length' "$all_results")"
    base_fail="$(jq '[.[] | select(.baseline_pass == false)] | length' "$all_results")"
    skill_pass="$(jq '[.[] | select(.skills_pass == true)] | length' "$all_results")"
    skill_fail="$(jq '[.[] | select(.skills_pass == false)] | length' "$all_results")"

    {
        echo "# libGDX Skills Test Report"
        echo ""
        echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
        echo "**Model:** \`$MODEL\` | **Adjudicator:** \`$ADJUDICATOR_MODEL\` | **Runs/arm:** $RUNS"
        echo "**Tests:** $total"
        echo ""
        echo "## Summary"
        echo ""
        echo "| Arm | Pass | Fail |"
        echo "|-----|------|------|"
        echo "| **Baseline** (no skills) | $base_pass | $base_fail |"
        echo "| **With skills** | $skill_pass | $skill_fail |"

        local base_total skill_total
        base_total=$((base_pass + base_fail))
        skill_total=$((skill_pass + skill_fail))
        if [[ $base_total -gt 0 && $skill_total -gt 0 ]]; then
            local base_rate skill_rate
            base_rate=$(( (base_pass * 100) / base_total ))
            skill_rate=$(( (skill_pass * 100) / skill_total ))
            echo ""
            echo "**Baseline pass rate:** ${base_rate}%"
            echo "**Skills pass rate:** ${skill_rate}%"
            echo "**Delta:** +$(( skill_rate - base_rate ))pp"
        fi

        # Confidence breakdown
        echo ""
        echo "## Adjudicator Confidence"
        echo ""
        echo "| Classification | Baseline | Skills |"
        echo "|---|---|---|"
        for cls in clear_pass clear_fail noise edge_case grader_error; do
            local bc sc
            bc="$(jq --arg c "$cls" '[.[] | select(.baseline_classification == $c)] | length' "$all_results")"
            sc="$(jq --arg c "$cls" '[.[] | select(.skills_classification == $c)] | length' "$all_results")"
            if [[ $bc -gt 0 || $sc -gt 0 ]]; then
                echo "| \`$cls\` | $bc | $sc |"
            fi
        done

        # Skills failures — only clear_fail and edge_case are actionable
        local actionable_failures
        actionable_failures="$(jq -r '.[] | select(.skills_pass == false and (.skills_classification == "clear_fail" or .skills_classification == "edge_case")) | "\(.id)\t\(.skills_classification)\t\(.skills_confidence)\t\(.skills_run_verdicts | map(if . then "✓" else "✗" end) | join(""))\t\(.skills_reason)"' "$all_results")"
        if [[ -n "$actionable_failures" ]]; then
            local af_count
            af_count="$(jq '[.[] | select(.skills_pass == false and (.skills_classification == "clear_fail" or .skills_classification == "edge_case"))] | length' "$all_results")"
            echo ""
            echo "## ❌ Actionable Skills Failures ($af_count)"
            echo ""
            echo "These are real skill gaps, not noise."
            echo ""
            while IFS=$'\t' read -r fid fclass fconf fruns freason; do
                echo "### \`$fid\` — $fclass ($fconf confidence)"
                echo "**Prompt:** $(get_test_field "$fid" "prompt")"
                echo "**Runs:** $fruns"
                echo "**Reason:** $freason"
                echo ""
            done <<< "$actionable_failures"
        fi

        # Noise — skills failures classified as noise
        local noise_failures
        noise_failures="$(jq -r '.[] | select(.skills_pass == false and .skills_classification == "noise") | "\(.id)\t\(.skills_run_verdicts | map(if . then "✓" else "✗" end) | join(""))\t\(.skills_reason)"' "$all_results")"
        if [[ -n "$noise_failures" ]]; then
            echo ""
            echo "## 🔇 Noise (not actionable)"
            echo ""
            echo "Adjudicator determined these failures are sampling variation."
            echo ""
            while IFS=$'\t' read -r nid nruns nreason; do
                echo "- \`$nid\` [$nruns]: $nreason"
            done <<< "$noise_failures"
        fi

        # Grader errors — adjudicator overruled the individual grades
        local grader_errors
        grader_errors="$(jq -r '.[] | select(.skills_classification == "grader_error" or .baseline_classification == "grader_error") | "\(.id)\t\(.skills_classification)\t\(.baseline_classification)\t\(.skills_reason)"' "$all_results")"
        if [[ -n "$grader_errors" ]]; then
            echo ""
            echo "## 🔧 Grader Errors (adjudicator overruled)"
            echo ""
            while IFS=$'\t' read -r gid gsc gbc greason; do
                echo "- \`$gid\`: skills=$gsc baseline=$gbc — $greason"
            done <<< "$grader_errors"
        fi

        # Regressions
        local regressions
        regressions="$(jq -r '.[] | select(.baseline_pass == true and .skills_pass == false) | "\(.id)\t\(.skills_classification)\t\(.skills_confidence)\t\(.skills_reason)"' "$all_results")"
        if [[ -n "$regressions" ]]; then
            echo ""
            echo "## ⚠️ Regressions"
            echo ""
            echo "Passed baseline, failed skills."
            echo ""
            while IFS=$'\t' read -r rid rclass rconf rreason; do
                echo "- \`$rid\` [$rclass, $rconf]: $rreason"
            done <<< "$regressions"
        fi

        # Improvements
        local improvements
        improvements="$(jq -r '.[] | select(.baseline_pass == false and .skills_pass == true) | "\(.id)\t\(.baseline_classification)\t\(.baseline_reason)"' "$all_results")"
        if [[ -n "$improvements" ]]; then
            local imp_count
            imp_count="$(jq '[.[] | select(.baseline_pass == false and .skills_pass == true)] | length' "$all_results")"
            echo ""
            echo "## ✅ Improvements ($imp_count)"
            echo ""
            echo "Failed baseline, passed with skills."
            echo ""
            while IFS=$'\t' read -r iid iclass ireason; do
                echo "- \`$iid\` [baseline was $iclass]: $ireason"
            done <<< "$improvements"
        fi

        # Full table
        echo ""
        echo "## Full Results"
        echo ""
        echo "| ID | Skill | Base | Skills | Confidence | Classification | Runs (B/S) |"
        echo "|-----|-------|------|--------|------------|----------------|------------|"
        jq -r '.[] | [
            .id, .skill,
            (if .baseline_pass == true then "✅" elif .baseline_pass == false then "❌" else "⏭️" end),
            (if .skills_pass == true then "✅" elif .skills_pass == false then "❌" else "⏭️" end),
            "\(.baseline_confidence)/\(.skills_confidence)",
            "\(.baseline_classification)/\(.skills_classification)",
            "\(.baseline_run_verdicts | map(if . then "✓" else "✗" end) | join("")) / \(.skills_run_verdicts | map(if . then "✓" else "✗" end) | join(""))"
        ] | "| `\(.[0])` | \(.[1][:18]) | \(.[2]) | \(.[3]) | \(.[4]) | \(.[5]) | \(.[6]) |"' "$all_results"

        # Per-skill
        echo ""
        echo "## Per-Skill Breakdown"
        echo ""
        jq -r 'group_by(.skill) | sort_by(.[0].skill) | .[] |
            (.[0].skill) as $skill |
            ([.[] | select(.skills_pass == true)] | length) as $sp |
            ([.[] | select(.skills_pass == false)] | length) as $sf |
            ($sp + $sf) as $total |
            (if $sf == 0 and $total > 0 then "✅" elif $sf > 0 then "❌" else "⏭️" end) as $icon |
            "\($icon) **\($skill)**: \($sp)/\($total)"
        ' "$all_results" | while IFS= read -r line; do echo "- $line"; done

    } > "$REPORT_FILE"

    # Terminal summary (reuse variables already computed above)
    echo ""
    echo "Report: $REPORT_FILE"
    echo ""
    echo "════════════════════════════════════════════════════"
    if [[ "$RUN_BASELINE" == "true" ]]; then
        echo "  Baseline: $base_pass pass / $base_fail fail"
    fi
    if [[ "$RUN_SKILLS" == "true" ]]; then
        echo "  Skills:   $skill_pass pass / $skill_fail fail"
    fi

    local actionable
    actionable="$(jq -r '.[] | select(.skills_pass == false and (.skills_classification == "clear_fail" or .skills_classification == "edge_case")) | "    ❌ \(.id) [\(.skills_classification), \(.skills_confidence)]: \(.skills_reason[:100])"' "$all_results")"
    if [[ -n "$actionable" ]]; then
        echo ""
        echo "  Actionable failures:"
        echo "$actionable"
    fi

    local noise_count
    noise_count="$(jq '[.[] | select(.skills_classification == "noise")] | length' "$all_results")"
    if [[ $noise_count -gt 0 ]]; then
        echo ""
        echo "  Noise (filtered): $noise_count test(s) — see report for details"
    fi
    echo "════════════════════════════════════════════════════"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    local test_ids
    mapfile -t test_ids < <(get_test_ids)
    local total=${#test_ids[@]}

    local arms_active=0
    [[ "$RUN_BASELINE" == "true" ]] && arms_active=$((arms_active + 1))
    [[ "$RUN_SKILLS" == "true" ]] && arms_active=$((arms_active + 1))
    local calls_per_arm=$(( RUNS * 2 + 1 ))
    local total_calls=$(( total * calls_per_arm * arms_active ))

    echo "════════════════════════════════════════════════════"
    echo "  Tests: $total | Runs/arm: $RUNS | Jobs: $JOBS"
    echo "  Model: $MODEL | Adjudicator: $ADJUDICATOR_MODEL"
    echo "  Baseline: $( [[ "$RUN_BASELINE" == "true" ]] && echo "ON" || echo "OFF" )"
    echo "  Skills:   $( [[ "$RUN_SKILLS" == "true" ]] && echo "ON" || echo "OFF" )"
    echo "  Est. claude calls: ~$total_calls"
    echo "════════════════════════════════════════════════════"
    echo ""

    local running=0

    for test_id in "${test_ids[@]}"; do
        run_test "$test_id" &
        running=$((running + 1))
        if [[ $running -ge $JOBS ]]; then
            wait -n 2>/dev/null || true
            running=$((running - 1))
        fi
    done
    wait 2>/dev/null || true

    echo ""
    echo "All tests complete. Generating report..."
    generate_report
}

main
