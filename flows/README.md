# Muntjac synthesis flows

Muntjac supports the following synthesis flows:

 * Verilator (software)
 * Vivado (FPGA)
 * OpenROAD (ASIC, free)
 * Synopsys (ASIC, commercial)

The main files in this directory are the `.core` files, which determine which source files and arguments are required for each build, and [FuseSoC](https://github.com/olofk/fusesoc) is then responsible for passing this information to the various tools.

## FuseSoC

### Install
```
pip install fusesoc
```

## Verilator

### Install (Ubuntu)
```
apt install verilator
```

### Lint
The goal is that if linting succeeds, the source will successfully build on any of the supported platforms.

```
fusesoc --cores-root=.. run --target=lint --tool=verilator lowrisc:muntjac:pipeline:0.1
```

### Build simulator
```
fusesoc --cores-root=.. run --target=sim --tool=verilator --build lowrisc:muntjac:pipeline:0.1
```

Once built, the simulator will be available at `./build/lowrisc_muntjac_pipeline_0.1/sim-verilator/muntjac_pipeline`.

### Run tests
RISC-V binaries can be executed using:

```
muntjac_pipeline [simulator arguments] <executable> [program arguments]
```

| Simulator argument | Description |
| --- | --- |
| `-memory-latency=X` | Set main memory latency to X cycles |
| `-timeout=X` | Force end of simulation after X cycles |
| `-v` | Display additional information as simulation proceeds |

## Vivado

## OpenROAD

### Install
OpenROAD provide their [own instructions](https://github.com/The-OpenROAD-Project/OpenROAD-flow/blob/master/README.md#installation).

## Synopsys
