# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import argparse
import csv

def compare_row(line, correct, test):
    for field in ["pc", "gpr", "csr", "binary", "mode"]:
        if correct[field] != test[field]:
            print("Divergence on line", line, ": expected", field,
                  correct[field], "but got", test[field])
            print("Instruction is", correct["instr_str"])
            exit(1)

def main():
    parser = argparse.ArgumentParser("RISCV-DV trace comparison script")
    parser.add_argument("--ref", type=str, required=True,
                        help="Reference trace file with assumed-correct behaviour.")
    parser.add_argument("--muntjac", type=str, required=True,
                        help="Muntjac trace file to compare against reference.")
    args = parser.parse_args()

    with open(args.ref, newline='') as reffile:
        ref = csv.DictReader(reffile)

        with open(args.muntjac, newline='') as muntjacfile:
            muntjac = csv.DictReader(muntjacfile)

            for line, (correct, test) in enumerate(zip(ref, muntjac)):
                compare_row(line, correct, test)

if __name__ == "__main__":
    main()
