# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import argparse
import csv

def compare_row(line, correct, test):
    # riscv-dv's Spike log parser discards everything after an `ecall`. If we've
    # reached this point without failing, the traces are considered equivalent.
    if correct["instr"] == "ecall":
        exit(0)

    for field in ["pc", "gpr", "csr", "binary", "mode"]:
        if correct[field] != test[field]:
            # Exceptions.
            # OVPsim doesn't output a register update if the value didn't change.
            if field == "gpr" and correct[field] == "":
                continue
            # Spike doesn't output any CSR updates.
            if field == "csr" and correct[field] == "":
                continue
            # Spike doesn't output a mode when no state is updated.
            if field == "mode" and correct[field] == "":
                continue
            # riscv-dv generates 64-bit instructions, which Spike displays in
            # full, but Muntjac doesn't even attempt to load.
            if field == "binary" and test[field] in correct[field]:
                continue

            print("Divergence on line", line, ": expected", field,
                  correct[field], "but got", test[field])
            print("Instruction is", correct["pc"], correct["instr_str"])
            exit(1)

def main():
    parser = argparse.ArgumentParser(description="RISCV-DV trace comparison script")
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
