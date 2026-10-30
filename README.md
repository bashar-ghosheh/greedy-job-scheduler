# Greedy Job Scheduler

A Bash implementation of deadline-based job sequencing. It reads jobs with a deadline, profit, duration, and penalty, validates the input, then schedules eligible work.

## Input format

Each non-comment line in the input file contains five whitespace-separated fields:

`job_id deadline profit duration penalty`

Example: see [jobs.txt](jobs.txt).

## Run

```bash
chmod +x main3.sh
./main3.sh jobs.txt
```

The scripts report invalid records and skip them. Test inputs are in [test_cases/](test_cases/).
