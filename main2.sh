#!/bin/sh

# Student1 Name: Bashar      std1 ID: 1230368
# Student2 Name: Tareq         std2 ID: 1230453

if [ "$#" -ne 1 ]; then
    echo "Please enter the input file"
    exit 1
fi

# Check the input file exists and is a regular file
if [ ! -f "$jobs.txt" ]; then
    echo "Input file not found or input file is not a regular file"
    exit 1
fi

# Handle empty input file edge case
if [ ! -s "$jobs.txt" ]; then
    echo "Input file is empty"
    exit 0
fi

T_VALID="/tmp/js_valid_$$"  # Validated jobs: net_val jid dl profit dur pen
T_SEEN="/tmp/js_seen_$$"    #used for duplicate detection
T_KEYFILE="/tmp/js_keys_$$" # Keyed jobs: sort_key net_val jid dl profit dur pen
T_SORTED="/tmp/js_sorted_$$" # Priority-sorted jobs (key stripped)
T_SLOTS="/tmp/js_slots_$$"  # Slot table: one line per slot ("0"=free, else job ID)
T_SLOTTMP="/tmp/js_stmp_$$" # Scratch for sed-based slot updates
T_SCHED="/tmp/js_sched_$$"  # Scheduled records : blk_start blk_end jid profit dur
T_SKIP="/tmp/js_skip_$$"    # Skipped records: jid penalty

# Initialize all writable temp files
touch "$T_VALID" "$T_SEEN" "$T_SCHED" "$T_SKIP"

echo "================================================================"
echo "  Job Sequencing Scheduler"
echo "  Input: $jobs.txt"
echo "================================================================"

line_num=0

while read -r line     
do

    # Skip blank lines
    if [ -z "$line" ]; then
        continue
    fi

    #Skip comment lines
    if [ "${line:0:1}" == "#" ]; then
        echo "found a comment line"
        continue
    fi

    jid=$(echo "$line" | cut -d  -f1)
    dl=$(echo "$line" | cut -d  -f2)
    profit=$(echo "$line" | cut -d  -f3)
    dur=$(echo "$line" | cut -d  -f4)
    pen=$(echo "$line" | cut -d  -f5)


    line_num=$((line_num + 1))

   
    # Fewer than 5 fields mean 'pen' is empty
    if [ -z "$pen" ]; then
        echo "Line $line_num has fewer than 5 fields."
        echo "Skipping..."
        continue
    fi

    # Ensure deadline is a non-negative integer (0 or more)
    if ! echo "$dl" | grep -q '^[0-9][0-9]*$'; then
        echo "Job '$jid' deadline '$dl' must be a positive integer. Skipping."
        continue
    fi

    # Ensure profit is a non-negative integer (0 or more)
    if ! echo "$profit" | grep -q '^[0-9][0-9]*$'; then
        echo "Job '$jid' profit '$profit' must be a non-negative integer. Skipping."
        continue
    fi

    # Ensure duration is a positive integer (1 or more)
    if ! echo "$dur" | grep -q '^[1-9][0-9]*$'; then
        echo "Job '$jid' duration '$dur' must be a positive integer. Skipping."
        continue
    fi

    # Ensure penalty is a non-negative integer (0 or more)
    if ! echo "$pen" | grep -q '^[0-9][0-9]*$'; then
        echo "Job '$jid' penalty '$pen' must be a non-negative integer. Skipping."
        continue
    fi

    # Check if duration is more than the deadline 
    if [ "$dur" -gt "$dl" ]; then
        echo "Job '$jid' duration ($dur) is more than deadline ($dl). Rejected."
        continue
    fi

    # Skip if job ID has already been seen
    if grep -q "^$jid$" "$T_SEEN"; then
        echo "Job '$jid' has duplicate ID at line $line_num. Skipping."
        continue
    fi
    echo "$jid" >> "$T_SEEN"   # Register ID as seen, this is used to check for duplicate jobs

    net_val=$((profit + pen))
    echo "$net_val $jid $dl $profit $dur $pen" >> "$T_VALID"
    echo "Accepted Job $jid, net value = $net_val"

done < "$jobs.txt"


# Abort early if nothing survived validation
if [ ! -s "$T_VALID" ]; then
    echo "No valid jobs found in '$jobs.txt'. Exiting."
    exit 0
fi


# ================================================================
# SECTION 3: SORTING Descending Net Value, Ascending Deadline
#             (Task 2)
#
# Problem: 'sort' in the notes only shows -n (numeric) and default
# (lexicographic). There is no -k (key) or -r (reverse) flag listed.
#
# Solution: Prepend a composite, zero-padded sort key to each line,
# then run a plain lexicographic 'sort'. The key is stripped after.
#
#   key = IIIIIII_DDDDDDD
#         IIIIIII = (9999999 - net_val)  → bigger net_val = smaller key = sorts first
#         DDDDDDD = deadline (zero-padded) → smaller deadline sorts first (tie-break)
# ================================================================
echo "[ Sorting jobs by priority... ]"

MAX_KEY=9999999

while read net_val jid dl profit dur pen; do
    inv=$((MAX_KEY - net_val))
    sort_key=$(printf "%07d_%07d" "$inv" "$dl")
    echo "$sort_key $net_val $jid $dl $profit $dur $pen"
done < "$T_VALID" | sort > "$T_KEYFILE"

# Strip the sort key restore clean job data format
while read sk net_val jid dl profit dur pen; do
    echo "$net_val $jid $dl $profit $dur $pen"
done < "$T_KEYFILE" > "$T_SORTED"

echo "  Done. Priority order established."
echo ""


# ================================================================
# SECTION 4: SLOT TABLE INITIALISATION   (Task 3 part 1)
#
# The total number of time slots equals the largest deadline across
# all valid jobs. Each slot is a line in T_SLOTS:
#   "0"    = free (available for assignment)
#   job_id = occupied by that job
# ================================================================
max_deadline=0
while read net_val jid dl profit dur pen; do
    if [ "$dl" -gt "$max_deadline" ]; then
        max_deadline=$dl
    fi
done < "$T_SORTED"

echo "[ Initialising $max_deadline time slot(s)... ]"

rm -f "$T_SLOTS"
s=1
while [ "$s" -le "$max_deadline" ]; do
    echo "0" >> "$T_SLOTS"
    s=$((s + 1))
done

echo "  Done."
echo ""


# ================================================================
# SECTION 5: GREEDY SLOT ASSIGNMENT   (Tasks 3, 4)
#
# Process jobs in priority order. For each job:
#   1. Start at the latest possible block: blk_start = dl - dur + 1
#   2. Check if all slots [blk_start .. blk_start+dur-1] are free
#   3. If yes → assign (mark slots with job ID, record profit)
#   4. If no  → try blk_start - 1; repeat until blk_start < 1
#   5. If no block found → skip the job and apply its penalty
# ================================================================
echo "[ Running greedy slot assignment... ]"

total_profit=0
total_penalty=0
scheduled_count=0
skipped_count=0

while read net_val jid dl profit dur pen; do

    assigned=0
    blk_start=$((dl - dur + 1))   # Latest start position within deadline

    # Walk backwards through possible start positions
    while [ "$blk_start" -ge 1 ]; do
        blk_end=$((blk_start + dur - 1))

        # ── Check every slot in the candidate block ────────────────
        all_free=1
        chk=$blk_start
        while [ "$chk" -le "$blk_end" ]; do
            # sed -n '${N}p' prints exactly line N of the slot table
            slot_val=$(sed -n "${chk}p" "$T_SLOTS")
            if [ "$slot_val" != "0" ]; then
                all_free=0
                break       # Block is blocked — stop checking early
            fi
            chk=$((chk + 1))
        done

        if [ "$all_free" -eq 1 ]; then
            # ── Claim the block: write job ID into each slot line ──
            # Pattern: sed '${N}s/.*/replacement/' overwrites line N
            s=$blk_start
            while [ "$s" -le "$blk_end" ]; do
                sed "${s}s/.*/$jid/" "$T_SLOTS" > "$T_SLOTTMP" \
                    && mv "$T_SLOTTMP" "$T_SLOTS"
                s=$((s + 1))
            done

            # Record scheduled job: blk_start blk_end jid profit dur
            echo "$blk_start $blk_end $jid $profit $dur" >> "$T_SCHED"
            total_profit=$((total_profit + profit))
            scheduled_count=$((scheduled_count + 1))
            assigned=1
            echo "  Scheduled: $jid  → slots $blk_start-$blk_end  (profit +$profit)"
            break
        fi

        blk_start=$((blk_start - 1))
    done

    # ── No block found: skip and record penalty ────────────────────
    if [ "$assigned" -eq 0 ]; then
        echo "$jid $pen" >> "$T_SKIP"
        total_penalty=$((total_penalty + pen))
        skipped_count=$((skipped_count + 1))
        echo "  Skipped:   $jid  (penalty -$pen)"
    fi

done < "$T_SORTED"

echo ""


# ================================================================
# SECTION 6: FINAL CALCULATIONS   (Task 4 — totals)
# ================================================================
net_profit=$((total_profit - total_penalty))
total_jobs=$((scheduled_count + skipped_count))


# ================================================================
# SECTION 7: OUTPUT BUILDER — Function (Tasks 5, 6)
#
# Defined as a shell function so the same formatted output is
# used for both the terminal (screen) and the results file,
# satisfying the modular design requirement.
# ================================================================
build_output() {
    echo "================================================================"
    echo "      JOB SEQUENCING WITH DEADLINES — FINAL RESULTS"
    echo "================================================================"
    echo ""

    # ── Scheduled jobs, sorted by start slot (sort -n = numeric) ──
    echo "SCHEDULED JOBS  (in time-slot order)"
    echo "----------------------------------------------------------------"
    printf "  %-10s  %-14s  %-10s  %-8s\n" \
           "Job ID" "Time Slots" "Profit" "Duration"
    printf "  %-10s  %-14s  %-10s  %-8s\n" \
           "----------" "--------------" "----------" "--------"

    if [ -s "$T_SCHED" ]; then
        sort -n "$T_SCHED" | while read ss se sjid sprofit sdur; do
            printf "  %-10s  %-14s  %-10s  %-8s\n" \
                   "$sjid" "${ss}-${se}" "$sprofit" "$sdur"
        done
    else
        echo "  (none scheduled)"
    fi

    echo ""

    # ── Skipped jobs ───────────────────────────────────────────────
    echo "SKIPPED JOBS"
    echo "----------------------------------------------------------------"
    printf "  %-10s  %-10s\n" "Job ID" "Penalty"
    printf "  %-10s  %-10s\n" "----------" "----------"

    if [ -s "$T_SKIP" ]; then
        while read sjid spen; do
            printf "  %-10s  %-10s\n" "$sjid" "$spen"
        done < "$T_SKIP"
    else
        echo "  (none)"
    fi

    echo ""

    # ── Summary ────────────────────────────────────────────────────
    echo "SUMMARY"
    echo "----------------------------------------------------------------"
    printf "  %-34s %s\n" "Total jobs considered:"    "$total_jobs"
    printf "  %-34s %s\n" "Jobs scheduled:"           "$scheduled_count"
    printf "  %-34s %s\n" "Jobs skipped:"             "$skipped_count"
    printf "  %-34s %s\n" "Total penalties applied:"  "$total_penalty"
    printf "  %-34s %s\n" "Gross profit (scheduled):" "$total_profit"
    printf "  %-34s %s\n" "Final net profit:"         "$net_profit"
    echo "================================================================"
}


# ================================================================
# SECTION 8: PRINT TO SCREEN   (Task 5)
# ================================================================
build_output


# ================================================================
# SECTION 9: WRITE TO output/result.txt   (Task 6)
#
# mkdir -p creates the directory only if it does not already exist
# (handles the edge case where 'output/' is missing).
# The { ... } command group redirects all enclosed output to the file.
# ================================================================

{
    printf "Timestamp  : %s\n" "$(date)"
    printf "Input File : %s\n" "$jobs.txt"
    echo ""
    build_output
} > "/result.txt"

echo ""
echo "Results saved to: result.txt"
