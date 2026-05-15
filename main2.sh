#!/usr/bin/env bash

# Student1 Name: Bashar      std1 ID: 1230368
# Student2 Name: Tareq       std2 ID: 1230453

set -u

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <input-file>"
  exit 1
fi

input_file="$1"

if [ ! -f "$input_file" ]; then
  echo "Input file not found or is not a regular file: $input_file"
  exit 1
fi

if [ ! -s "$input_file" ]; then
  echo "Input file is empty"
  exit 0
fi

echo "================================================================"
echo "  Job Sequencing Scheduler"
echo "  Input: $input_file"
echo "================================================================"

# -------------------------------
# Arrays that store valid jobs
# -------------------------------
declare -a job_ids deadlines profits durations penalties net_values

line_num=0

while IFS= read -r line; do
  line_num=$((line_num + 1))

  # skip blank lines
  [ -z "$line" ] && continue

  # skip comment lines
  case "$line" in
    \#*)
      continue
      ;;
  esac

  # split by whitespace into 5 expected fields
  read -r jid dl profit dur pen extra <<< "$line"

  if [ -n "${extra:-}" ] || [ -z "${pen:-}" ]; then
    echo "Line $line_num must have exactly 5 fields. Skipping."
    continue
  fi

  if ! [[ "$dl" =~ ^[0-9]+$ ]]; then
    echo "Job '$jid' deadline '$dl' must be a non-negative integer. Skipping."
    continue
  fi

  if ! [[ "$profit" =~ ^[0-9]+$ ]]; then
    echo "Job '$jid' profit '$profit' must be a non-negative integer. Skipping."
    continue
  fi

  if ! [[ "$dur" =~ ^[1-9][0-9]*$ ]]; then
    echo "Job '$jid' duration '$dur' must be a positive integer. Skipping."
    continue
  fi

  if ! [[ "$pen" =~ ^[0-9]+$ ]]; then
    echo "Job '$jid' penalty '$pen' must be a non-negative integer. Skipping."
    continue
  fi

  if [ "$dur" -gt "$dl" ]; then
    echo "Job '$jid' duration ($dur) is more than deadline ($dl). Skipping."
    continue
  fi

  # duplicate ID check (simple beginner-friendly loop)
  duplicate=0
  for seen_id in "${job_ids[@]}"; do
    if [ "$seen_id" = "$jid" ]; then
      duplicate=1
      break
    fi
  done

  if [ "$duplicate" -eq 1 ]; then
    echo "Job '$jid' has duplicate ID at line $line_num. Skipping."
    continue
  fi

  net_val=$((profit + pen))

  job_ids+=("$jid")
  deadlines+=("$dl")
  profits+=("$profit")
  durations+=("$dur")
  penalties+=("$pen")
  net_values+=("$net_val")

  echo "Accepted Job $jid, net value = $net_val"
done < "$input_file"

job_count=${#job_ids[@]}
if [ "$job_count" -eq 0 ]; then
  echo "No valid jobs found in '$input_file'. Exiting."
  exit 0
fi

# -------------------------------
# Sort jobs by:
# 1) net value descending
# 2) deadline ascending
# -------------------------------
declare -a order
for ((i=0; i<job_count; i++)); do
  order+=("$i")
done

for ((i=0; i<job_count; i++)); do
  for ((j=i+1; j<job_count; j++)); do
    a=${order[i]}
    b=${order[j]}

    swap=0
    if [ "${net_values[b]}" -gt "${net_values[a]}" ]; then
      swap=1
    elif [ "${net_values[b]}" -eq "${net_values[a]}" ] && [ "${deadlines[b]}" -lt "${deadlines[a]}" ]; then
      swap=1
    fi

    if [ "$swap" -eq 1 ]; then
      tmp=${order[i]}
      order[i]=${order[j]}
      order[j]=$tmp
    fi
  done
done

# -------------------------------
# Build time slots array
# -------------------------------
max_deadline=0
for dl in "${deadlines[@]}"; do
  if [ "$dl" -gt "$max_deadline" ]; then
    max_deadline=$dl
  fi
done

# slots are 1-indexed for easier reading
# value "0" means free
slots=("unused")
for ((s=1; s<=max_deadline; s++)); do
  slots+=("0")
done

# -------------------------------
# Greedy assignment
# -------------------------------
declare -a sched_start sched_end sched_id sched_profit sched_duration

declare -a skipped_id skipped_penalty

total_profit=0
total_penalty=0

for idx in "${order[@]}"; do
  jid=${job_ids[idx]}
  dl=${deadlines[idx]}
  profit=${profits[idx]}
  dur=${durations[idx]}
  pen=${penalties[idx]}

  assigned=0
  start=$((dl - dur + 1))

  while [ "$start" -ge 1 ]; do
    end=$((start + dur - 1))

    all_free=1
    for ((t=start; t<=end; t++)); do
      if [ "${slots[t]}" != "0" ]; then
        all_free=0
        break
      fi
    done

    if [ "$all_free" -eq 1 ]; then
      for ((t=start; t<=end; t++)); do
        slots[t]="$jid"
      done

      sched_start+=("$start")
      sched_end+=("$end")
      sched_id+=("$jid")
      sched_profit+=("$profit")
      sched_duration+=("$dur")

      total_profit=$((total_profit + profit))
      assigned=1
      echo "Scheduled: $jid -> slots $start-$end (profit +$profit)"
      break
    fi

    start=$((start - 1))
  done

  if [ "$assigned" -eq 0 ]; then
    skipped_id+=("$jid")
    skipped_penalty+=("$pen")
    total_penalty=$((total_penalty + pen))
    echo "Skipped:   $jid (penalty -$pen)"
  fi
done

scheduled_count=${#sched_id[@]}
skipped_count=${#skipped_id[@]}
net_profit=$((total_profit - total_penalty))

build_output() {
  echo "================================================================"
  echo "      JOB SEQUENCING WITH DEADLINES — FINAL RESULTS"
  echo "================================================================"
  echo

  echo "SCHEDULED JOBS (in chosen order)"
  echo "----------------------------------------------------------------"
  printf "  %-10s  %-14s  %-10s  %-8s\n" "Job ID" "Time Slots" "Profit" "Duration"
  printf "  %-10s  %-14s  %-10s  %-8s\n" "----------" "--------------" "----------" "--------"

  if [ "$scheduled_count" -eq 0 ]; then
    echo "  (none scheduled)"
  else
    for ((i=0; i<scheduled_count; i++)); do
      printf "  %-10s  %-14s  %-10s  %-8s\n" \
        "${sched_id[i]}" "${sched_start[i]}-${sched_end[i]}" "${sched_profit[i]}" "${sched_duration[i]}"
    done
  fi

  echo
  echo "SKIPPED JOBS"
  echo "----------------------------------------------------------------"
  printf "  %-10s  %-10s\n" "Job ID" "Penalty"
  printf "  %-10s  %-10s\n" "----------" "----------"

  if [ "$skipped_count" -eq 0 ]; then
    echo "  (none)"
  else
    for ((i=0; i<skipped_count; i++)); do
      printf "  %-10s  %-10s\n" "${skipped_id[i]}" "${skipped_penalty[i]}"
    done
  fi

  echo
  echo "SUMMARY"
  echo "----------------------------------------------------------------"
  printf "  %-34s %s\n" "Total jobs considered:" "$job_count"
  printf "  %-34s %s\n" "Jobs scheduled:" "$scheduled_count"
  printf "  %-34s %s\n" "Jobs skipped:" "$skipped_count"
  printf "  %-34s %s\n" "Total penalties applied:" "$total_penalty"
  printf "  %-34s %s\n" "Gross profit (scheduled):" "$total_profit"
  printf "  %-34s %s\n" "Final net profit:" "$net_profit"
  echo "================================================================"
}

build_output

mkdir -p output
{
  printf "Timestamp  : %s\n" "$(date)"
  printf "Input File : %s\n\n" "$input_file"
  build_output
} > output/result.txt

echo
echo "Results saved to: output/result.txt"
