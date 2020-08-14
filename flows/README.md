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
fusesoc init
```

## Verilator

### Install (Ubuntu)
```
apt install verilator
```

### Lint
```
fusesoc --cores-root . run --target=lint --tool=verilator lowrisc:muntjac:muntjac_pipeline:0.1
```

### Run tests

## Vivado

## OpenROAD

### Install
OpenROAD provide their [own instructions](https://github.com/The-OpenROAD-Project/OpenROAD-flow/blob/master/README.md#installation).

## Synopsys
