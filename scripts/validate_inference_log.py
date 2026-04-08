import argparse
import re
import sys
from pathlib import Path

START_RE = re.compile(r"^\[START\] task=[^\s]+ env=[^\s]+ model=[^\s]+$")
STEP_RE = re.compile(
    r"^\[STEP\] step=\d+ action=.+ reward=\d+\.\d{2} done=(true|false) error=(null|.+)$"
)
END_RE = re.compile(r"^\[END\] success=(true|false) steps=\d+ rewards=([0-9]+\.\d{2}(,[0-9]+\.\d{2})*)?$")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate inference structured log format")
    parser.add_argument("--log", required=True, help="Path to inference log file")
    args = parser.parse_args()

    log_path = Path(args.log)
    if not log_path.exists():
        print(f"[FAIL] log file not found: {log_path}")
        return 1

    lines = [line.rstrip("\n") for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not lines:
        print("[FAIL] log file is empty")
        return 1

    start_tasks: list[str] = []
    end_tasks: list[str] = []
    expect_start = True
    saw_step = False
    current_task = None

    for idx, line in enumerate(lines, start=1):
        if line.startswith("[START]"):
            if not START_RE.match(line):
                print(f"[FAIL] invalid START line at {idx}: {line}")
                return 1
            if current_task is not None:
                print(f"[FAIL] START encountered before END at {idx}: {line}")
                return 1
            current_task = line.split()[1].split("=", 1)[1]
            start_tasks.append(current_task)
            expect_start = False
            continue

        if line.startswith("[STEP]"):
            if current_task is None:
                print(f"[FAIL] STEP encountered before START at {idx}: {line}")
                return 1
            if not STEP_RE.match(line):
                print(f"[FAIL] invalid STEP line at {idx}: {line}")
                return 1
            saw_step = True
            expect_start = False
            continue

        if line.startswith("[END]"):
            if current_task is None:
                print(f"[FAIL] END encountered before START at {idx}: {line}")
                return 1
            if not END_RE.match(line):
                print(f"[FAIL] invalid END line at {idx}: {line}")
                return 1
            end_tasks.append(current_task)
            current_task = None
            expect_start = True
            continue

        print(f"[FAIL] unexpected line at {idx}: {line}")
        return 1

    required_tasks = {"task_1", "task_2", "task_3"}
    if set(start_tasks) != required_tasks:
        missing = sorted(required_tasks - set(start_tasks))
        extra = sorted(set(start_tasks) - required_tasks)
        if missing:
            print(f"[FAIL] missing START for tasks: {', '.join(missing)}")
        else:
            print(f"[FAIL] unexpected START tasks: {', '.join(extra)}")
        return 1
    if set(end_tasks) != required_tasks:
        missing = sorted(required_tasks - set(end_tasks))
        extra = sorted(set(end_tasks) - required_tasks)
        if missing:
            print(f"[FAIL] missing END for tasks: {', '.join(missing)}")
        else:
            print(f"[FAIL] unexpected END tasks: {', '.join(extra)}")
        return 1

    if current_task is not None:
        print(f"[FAIL] missing END for task: {current_task}")
        return 1
    if not saw_step:
        print("[FAIL] no STEP lines found")
        return 1

    print(f"[PASS] START={len(start_tasks)} STEP lines present END={len(end_tasks)}")
    print("[PASS] required task markers present: task_1, task_2, task_3")
    return 0


if __name__ == "__main__":
    sys.exit(main())
