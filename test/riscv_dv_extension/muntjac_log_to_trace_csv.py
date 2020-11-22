# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""
Convert the output of muntjac's `--csv` option to the required CSV format for
riscv-dv. The output is already a CSV, but some changes need to be made:
 * Decode the instruction binary to get
   - Instruction name
   - Instruction string
   - Instruction operands
 * Convert register/CSR indices to names
 * Add empty padding column

Note that the instruction string (and derivative fields) are not necessary for
equivalence checking, and so are only generated with best effort (i.e. the
format may not be standard, or the instruction may not be decoded successfully).
"""

import argparse
from collections import OrderedDict
import csv
from riscvmodel.code import decode, MachineDecodeError

gpr_names = {
    0:  "zero",
    1:  "ra",
    2:  "sp",
    3:  "gp",
    4:  "tp",
    5:  "t0",
    6:  "t1",
    7:  "t2",
    8:  "s0",
    9:  "s1",
    10: "a0",
    11: "a1",
    12: "a2",
    13: "a3",
    14: "a4",
    15: "a5",
    16: "a6",
    17: "a7",
    18: "s2",
    19: "s3",
    20: "s4",
    21: "s5",
    22: "s6",
    23: "s7",
    24: "s8",
    25: "s9",
    26: "s10",
    27: "s11",
    28: "t3",
    29: "t4",
    30: "t5",
    31: "t6"
}

csr_names = {
    0: "ustatus",
    4: "uie",
    5: "utvec",
    64: "uscratch",
    65: "uepc",
    66: "ucause",
    67: "utval",
    68: "uip",
    1: "fflags",
    2: "frm",
    3: "fcsr",
    3072: "cycle",
    3073: "time",
    3074: "instret",
    3075: "hpmcounter3",
    3076: "hpmcounter4",
    3077: "hpmcounter5",
    3078: "hpmcounter6",
    3079: "hpmcounter7",
    3080: "hpmcounter8",
    3081: "hpmcounter9",
    3082: "hpmcounter10",
    3083: "hpmcounter11",
    3084: "hpmcounter12",
    3085: "hpmcounter13",
    3086: "hpmcounter14",
    3087: "hpmcounter15",
    3088: "hpmcounter16",
    3089: "hpmcounter17",
    3090: "hpmcounter18",
    3091: "hpmcounter19",
    3092: "hpmcounter20",
    3093: "hpmcounter21",
    3094: "hpmcounter22",
    3095: "hpmcounter23",
    3096: "hpmcounter24",
    3097: "hpmcounter25",
    3098: "hpmcounter26",
    3099: "hpmcounter27",
    3100: "hpmcounter28",
    3101: "hpmcounter29",
    3102: "hpmcounter30",
    3103: "hpmcounter31",
    3200: "cycleh",
    3201: "timeh",
    3202: "instreth",
    3203: "hpmcounter3h",
    3204: "hpmcounter4h",
    3205: "hpmcounter5h",
    3206: "hpmcounter6h",
    3207: "hpmcounter7h",
    3208: "hpmcounter8h",
    3209: "hpmcounter9h",
    3210: "hpmcounter10h",
    3211: "hpmcounter11h",
    3212: "hpmcounter12h",
    3213: "hpmcounter13h",
    3214: "hpmcounter14h",
    3215: "hpmcounter15h",
    3216: "hpmcounter16h",
    3217: "hpmcounter17h",
    3218: "hpmcounter18h",
    3219: "hpmcounter19h",
    3220: "hpmcounter20h",
    3221: "hpmcounter21h",
    3222: "hpmcounter22h",
    3223: "hpmcounter23h",
    3224: "hpmcounter24h",
    3225: "hpmcounter25h",
    3226: "hpmcounter26h",
    3227: "hpmcounter27h",
    3228: "hpmcounter28h",
    3229: "hpmcounter29h",
    3230: "hpmcounter30h",
    3231: "hpmcounter31h",
    256: "sstatus",
    258: "sedeleg",
    259: "sideleg",
    260: "sie",
    261: "stvec",
    262: "scounteren",
    320: "sscratch",
    321: "sepc",
    322: "scause",
    323: "stval",
    324: "sip",
    384: "satp",
    3857: "mvendorid",
    3858: "marchid",
    3859: "mimpid",
    3860: "mhartid",
    768: "mstatus",
    769: "misa",
    770: "medeleg",
    771: "mideleg",
    772: "mie",
    773: "mtvec",
    774: "mcounteren",
    832: "mscratch",
    833: "mepc",
    834: "mcause",
    835: "mtval",
    836: "mip",
    928: "pmpcfg0",
    929: "pmpcfg1",
    930: "pmpcfg2",
    931: "pmpcfg3",
    944: "pmpaddr0",
    945: "pmpaddr1",
    946: "pmpaddr2",
    947: "pmpaddr3",
    948: "pmpaddr4",
    949: "pmpaddr5",
    950: "pmpaddr6",
    951: "pmpaddr7",
    952: "pmpaddr8",
    953: "pmpaddr9",
    954: "pmpaddr10",
    955: "pmpaddr11",
    956: "pmpaddr12",
    957: "pmpaddr13",
    958: "pmpaddr14",
    959: "pmpaddr15",
    2816: "mcycle",
    2818: "minstret",
    2819: "mhpmcounter3",
    2820: "mhpmcounter4",
    2821: "mhpmcounter5",
    2822: "mhpmcounter6",
    2823: "mhpmcounter7",
    2824: "mhpmcounter8",
    2825: "mhpmcounter9",
    2826: "mhpmcounter10",
    2827: "mhpmcounter11",
    2828: "mhpmcounter12",
    2829: "mhpmcounter13",
    2830: "mhpmcounter14",
    2831: "mhpmcounter15",
    2832: "mhpmcounter16",
    2833: "mhpmcounter17",
    2834: "mhpmcounter18",
    2835: "mhpmcounter19",
    2836: "mhpmcounter20",
    2837: "mhpmcounter21",
    2838: "mhpmcounter22",
    2839: "mhpmcounter23",
    2840: "mhpmcounter24",
    2841: "mhpmcounter25",
    2842: "mhpmcounter26",
    2843: "mhpmcounter27",
    2844: "mhpmcounter28",
    2845: "mhpmcounter29",
    2846: "mhpmcounter30",
    2847: "mhpmcounter31",
    2944: "mcycleh",
    2946: "minstreth",
    2947: "mhpmcounter3h",
    2948: "mhpmcounter4h",
    2949: "mhpmcounter5h",
    2950: "mhpmcounter6h",
    2951: "mhpmcounter7h",
    2952: "mhpmcounter8h",
    2953: "mhpmcounter9h",
    2954: "mhpmcounter10h",
    2955: "mhpmcounter11h",
    2956: "mhpmcounter12h",
    2957: "mhpmcounter13h",
    2958: "mhpmcounter14h",
    2959: "mhpmcounter15h",
    2960: "mhpmcounter16h",
    2961: "mhpmcounter17h",
    2962: "mhpmcounter18h",
    2963: "mhpmcounter19h",
    2964: "mhpmcounter20h",
    2965: "mhpmcounter21h",
    2966: "mhpmcounter22h",
    2967: "mhpmcounter23h",
    2968: "mhpmcounter24h",
    2969: "mhpmcounter25h",
    2970: "mhpmcounter26h",
    2971: "mhpmcounter27h",
    2972: "mhpmcounter28h",
    2973: "mhpmcounter29h",
    2974: "mhpmcounter30h",
    2975: "mhpmcounter31h",
    803: "mhpmevent3",
    804: "mhpmevent4",
    805: "mhpmevent5",
    806: "mhpmevent6",
    807: "mhpmevent7",
    808: "mhpmevent8",
    809: "mhpmevent9",
    810: "mhpmevent10",
    811: "mhpmevent11",
    812: "mhpmevent12",
    813: "mhpmevent13",
    814: "mhpmevent14",
    815: "mhpmevent15",
    816: "mhpmevent16",
    817: "mhpmevent17",
    818: "mhpmevent18",
    819: "mhpmevent19",
    820: "mhpmevent20",
    821: "mhpmevent21",
    822: "mhpmevent22",
    823: "mhpmevent23",
    824: "mhpmevent24",
    825: "mhpmevent25",
    826: "mhpmevent26",
    827: "mhpmevent27",
    828: "mhpmevent28",
    829: "mhpmevent29",
    830: "mhpmevent30",
    831: "mhpmevent31",
    1952: "tselect",
    1953: "tdata1",
    1954: "tdata2",
    1955: "tdata3",
    1968: "dcsr",
    1969: "dpc",
    1970: "dscratch",
    512: "hstatus",
    514: "hedeleg",
    515: "hideleg",
    516: "hie",
    517: "htvec",
    576: "hscratch",
    577: "hepc",
    578: "hcause",
    579: "hbadaddr",
    580: "hip",
    896: "mbase",
    897: "mbound",
    898: "mibase",
    899: "mibound",
    900: "mdbase",
    901: "mdbound",
    800: "mcountinhibit"
}

def translate_gpr(text):
    """Convert text of the form "reg_index:value" to "reg_name:value"."""
    if text == "":
        return text

    parts = text.split(":")
    reg_index = int(parts[0], 16)
    value = parts[1]
    reg_name = gpr_names[reg_index];
    return reg_name + ":" + value

def translate_csr(text):
    """Convert text of the form "csr_index:value" to "csr_name:value"."""
    if text == "":
        return text

    parts = text.split(":")
    csr_index = int(parts[0], 16)
    value = parts[1]
    csr_name = csr_names[csr_index];
    return csr_name + ":" + value

riscv_dv_fields = [
    "pc",           # Program counter (in hex format)
    "instr",        # Instruction name
    "gpr",          # General purpose register update (format: "reg:value")
    "csr",          # Control/status register update (format: "reg:value")
    "binary",       # Encoded instruction (in hex format)
    "mode",         # Privilege mode (in integer format)
    "instr_str",    # Decoded instruction string
    "operand",      # Decoded instruction string, minus the instruction name
    "pad"           # Padding: empty
]

def translate_row(row):
    """Translate a single row of data from Muntjac simulator format to riscv-dv
    format."""
    new_row = OrderedDict()

    new_row["pc"] = row["pc"]       # TODO: zero pad?
    new_row["instr"] = "unknown"
    new_row["gpr"] = translate_gpr(row["gpr"])
    new_row["csr"] = translate_csr(row["csr"])
    new_row["binary"] = row["binary"]
    new_row["mode"] = row["mode"]
    new_row["instr_str"] = "unknown"
    new_row["operand"] = "unknown"
    new_row["pad"] = ""

    try:
        # The `decude` function supports a `variant` argument specifying the
        # allowed instruction set extensions, but at the time of writing, it
        # makes the output worse.
        decoded = str(decode(int(row["binary"], 16)))
        parts = decoded.split(maxsplit=1)
        new_row["instr"] = parts[0]
        new_row["instr_str"] = decoded
        new_row["operand"] = parts[1] if len(parts) > 1 else ""
    except MachineDecodeError:
        # riscvmodel isn't yet able to decode all instructions.
        # This isn't a fatal error: the instruction strings are not necessary
        # when comparing traces, so long as the program counter is included.
        pass

    return new_row

def main():
    parser = argparse.ArgumentParser("RISCV-DV trace translation script")
    parser.add_argument("--log", type=str, required=True,
                        help="Log file produced using `muntjac --csv`")
    parser.add_argument("--csv", type=str, required=True,
                        help="Location to store output. Must be separate from input.")
    args = parser.parse_args()

    with open(args.log, newline='') as logfile:
        reader = csv.DictReader(logfile)

        with open(args.csv, 'w', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=riscv_dv_fields)

            writer.writeheader()

            for row in reader:
                writer.writerow(translate_row(row))

if __name__ == "__main__":
    main()
