# Muntjac synthesis flows

Muntjac supports the following synthesis flows:

 * Verilator (software)
 * Vivado (FPGA)
 * ~~OpenROAD (ASIC, free)~~
 * ~~Synopsys (ASIC, commercial)~~

This directory contains scripts and other auxiliary files required to exercise these tools, and also [`.core` files](https://fusesoc.readthedocs.io/en/master/ref/capi2.html), which determine which source files and arguments are required for each build.

## Verilator
Tested on Ubuntu >= 16.04.

### Setup
We currently require newer versions of [Verilator](https://www.veripool.org/wiki/verilator), [FuseSoC](https://github.com/olofk/fusesoc) and [Edalize](https://github.com/olofk/edalize) than most package managers provide:

```
curl -Ls https://download.opensuse.org/repositories/home:phiwag:edatools/xUbuntu_20.04/Release.key | sudo apt-key add -
sudo sh -c "echo 'deb http://download.opensuse.org/repositories/home:/phiwag:/edatools/xUbuntu_20.04/ /' > /etc/apt/sources.list.d/edatools.list"
sudo apt-get update
sudo apt-get install verilator-4.200

pip3 install -r python-requirements.txt
```

### Linting
If linting succeeds, the source should successfully build on any of the supported platforms. From Muntjac's root directory:

```
make lint
```

### Simulation
From Muntjac's root directory:

```
make sim
```

Once built, the simulator will be available at `bin/muntjac_core`. It is also possible to `make sim-pipeline` for a slightly faster simulator which does not model the cache hierarchy.

RISC-V binaries can be executed using:

```
muntjac_core [simulator arguments] <executable> [program arguments]
```

| Simulator argument | Description |
| --- | --- |
| `--csv=X` | Output CSV (comma separated value) data to file X, describing instructions executed and state modified. Used mainly for [riscv-dv](https://github.com/google/riscv-dv). |
| `--help` | Display usage information. |
| `--memory-latency=X` | Set main memory latency to X cycles. |
| `--timeout=X` | Force end of simulation after X cycles. |
| `--vcd=X` | Dump VCD output to file X. |
| `-v[v]` | Display additional information as simulation proceeds. More `v`s gives more output. |

