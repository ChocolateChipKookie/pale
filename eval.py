#!/usr/bin/env python3
import subprocess
import re
import statistics

def parse_metrics(output: str) -> dict[str, float]:
    """Extract metrics from command output."""
    metrics = {}
    patterns = {
        'iterations': r'Iterations:\s+(\d+)',
        'seconds': r'Seconds:\s+([\d.]+)',
        'iters_per_second': r'Iters/second:\s+([\d.]+)',
        'normalized_error': r'Normalized error:\s+([\d.]+)'
    }

    for key, pattern in patterns.items():
        match = re.search(pattern, output)
        if match:
            metrics[key] = float(match.group(1))

    return metrics

def main():
    runs = 10
    all_metrics = {
        'iterations': [],
        'seconds': [],
        'iters_per_second': [],
        'normalized_error': []
    }

    for i in range(1, runs + 1):
        print(f"Run {i}/{runs}...", flush=True)
        result = subprocess.run(
            ['zig', 'build', 'run', '--release=fast'],
            capture_output=True,
            text=True,
            check=True
        )

        metrics = parse_metrics(result.stdout)
        for key, value in metrics.items():
            all_metrics[key].append(value)

    print("\n" + "="*50)
    print("Mean values:")
    print("="*50)
    for key, values in all_metrics.items():
        mean = statistics.mean(values)
        print(f"{key.replace('_', ' ').title()}: {mean}")

if __name__ == '__main__':
    main()
