# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import argparse
import re

def report_coverage(hit, total):
    if total == 0:
        print("No coverpoints found")
    else:
        print(f"{hit}/{total} ({hit/total:.0%})")


def collect_coverage(annotation_dir, files):
    coverpoints_total = 0
    coverpoints_hit = 0

    # All missed coverpoint lines start with "%000000".
    # Hit coverpoint lines start with e.g.   " 173092".
    # Lines with no coverpoints start with   "       ".
    missed = re.compile("^%000000")
    hit = re.compile("^ [0-9]{6}")

    for filename in files:
        try:
            with open(annotation_dir + "/" + filename, "r") as f:
                for line in f:
                    if re.match(missed, line):
                        coverpoints_total += 1
                    elif re.match(hit, line):
                        coverpoints_total += 1
                        coverpoints_hit += 1
        except FileNotFoundError:
            # Verilator doesn't annotate a file if there are no coverpoints.
            # This is not an issue.
            pass
    
    return coverpoints_hit, coverpoints_total


def main():
    parser = argparse.ArgumentParser(description="Aggregate coverage information from a subset of the available files")
    parser.add_argument("--annotation-dir", type=str, required=True,
                        help="Directory containing Verilator coverage annotations")
    parser.add_argument("--files", nargs="+", required=True,
                        help="List of filenames to accumulate coverage data from")
    args = parser.parse_args()

    results = collect_coverage(args.annotation_dir, args.files)
    report_coverage(*results)


if __name__ == "__main__":
    main()
