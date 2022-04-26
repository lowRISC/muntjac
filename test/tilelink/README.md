# TileLink verification
A collection of tools used to test and verify Muntjac's TileLink IP.

For each of the TileLink protocol variants (TL-UL, TL-UH, TL-C), we provide:
 * A module which monitors a TileLink channel and checks that all communication adheres to the TileLink specification.
 * A collection of functional coverage points, enumerating all of the states we want to see when testing.

We also provide a random traffic generator to exercise as many states as possible.

All code targets [TileLink 1.8](https://sifive.cdn.prismic.io/sifive/7bef6f5c-ed3a-4712-866a-1a2e0c6b7b13_tilelink_spec_1.8.1.pdf).

## Components verified
The following components have been verified using the methodology below:
 * `tl_adapter`
 * `tl_broadcast`
 * `tl_data_downsizer`
 * `tl_data_upsizer`
 * `tl_fifo_async`
 * `tl_fifo_converter`
 * `tl_fifo_sync`
 * `tl_io_terminator`
 * `tl_ram_terminator`
 * `tl_regslice`
 * `tl_rom_terminator`
 * `tl_sink_upsizer`
 * `tl_size_downsizer`
 * `tl_socket_1n`
 * `tl_socket_m1`
 * `tl_source_downsizer`
 * `tl_source_shifter`

## Assertions
Assertions check compliance with the TileLink specification, ensuring that each message is self-consistent, that consecutive beats within a burst message are consistent with each other, and that responses are consistent with the requests that triggered them. Assertions are checked automatically when collecting coverage data.

To enable assertions in a system-level Muntjac simulator, pass the `assertions_on` flag during the build process, for example:

```
make sim-core EXTRA_FLAGS=assertions_on
```

Note that assertions add a significant penalty to simulation speed. We aim to provide sufficiently thorough verification of the TileLink components that assertions are not needed in system-level tests.


## Coverage
Coverage aims to quantify how much of the state space has been explored during testing.

To generate a coverage data for a component using random traffic, run `make DUT=component_name`. This will produce an output along the lines of:

```
No assertions triggered
Line coverage, DUT only (25/25) 100%
Functional coverage (72/72) 100%
```

Note that line coverage is reported only for the tested component, and not any subcomponents. Depending on how the DUT uses its subcomponents, it may not be possible to achieve a high coverage. It is assumed that subcomponents will be tested in isolation elsewhere.

The length of simulation can be controlled using `make CYCLES=X` and a different random seed can be selected using `make SEED=X`.

### Coverpoints
To see which coverpoints were reached during simulation, look through the `coverage` directory. This will contain copies of SystemVerilog source files, with annotations describing how many time each coverpoint was reached. "Next point on previous line" indicates that multiple coverpoints were on the same line of source code.

The default functional coverpoints are:
 * For each channel (`A`, `B`, `C`, `D`, `E`):
   * Two messages were sent with/without a pause between them
   * A valid message was/was not accepted by the recipient
   * The corrupt/denied bits were used (if appropriate)
 * For each field (e.g. `A.address`, `D.data`):
   * Consecutive messages used the same/different values
   * The value changed/stayed the same while waiting for a message to be accepted

TODO:
 * For the whole system
   * Messages were sent/received simultaneously by every combination of endpoints
 * For each endpoint (host, device):
   * Messages were sent/received simultaneously on every combination of channels


## Debugging
If an assertion fails, it may be useful to invoke the simulator directly to collect additional information.

```
make sim DUT=component_name
```

This generates a number of simulators, each with different parametrisations of the component, all with the following command line options:

| Argument | Description |
| --- | --- |
| `--help` | Display usage information and exit |
| `--run X` | Generate random traffic for the given duration (in cycles) |
| `--random-seed X `| Set the random seed |
| `--config X` | Configure simulation using a YAML file. This must match the configuration of the Verilog module. |
| `--coverage X` | Dump coverage information to file `X` |
| `--vcd/fst X` | Dump waveform output to a file. Only one format can be enabled at a time: see the testbench `.core` files to change which one (requires simulator to be rebuilt). |
| `-v[v]` | Display debug information as simulation proceeds |


## Configuration
We provide a range of configurations to be tested for each component. This can be found in `configs.yaml` in any of the component subdirectories of [configs](configs).

This file describes the parameter names required by the SystemVerilog module, and the values of those parameters to be tested. A single configuration file may contain details of many configurations to test.

Use `configs/tl_config_generator.py` to select a single configuration and generate consistent settings files to pass to SystemVerilog and Verilator.


## Limitations
 * Test modules assume that no TileLink signals are updated on the negative clock edge.
 * Transactions involving the B channel are verified less rigorously. This is because the B channel allows too many outstanding requests to keep track of.
 * Muntjac's TileLink IP does not support forwarding of A messages to the B channel, or C messages to the D channel. None of this behaviour is supported by the verification tools either.
 * If a component modifies a message in some way (e.g. breaking a message into multiple smaller messages), it is not possible to verify whether this was done correctly, only whether the result is a valid TileLink message.


## Extension
To add new assertions or coverpoints, see [`tl_assert.sv`](rtl/tl_assert.sv) and [`tl_cover.sv`](rtl/tl_cover.sv).

To apply assertions and coverage to a new component, see [`tl_checker.sv`](rtl/tl_checker.sv) and [`tl_bind.sv`](rtl/tl_bind.sv).

To test a new component, provide a new subdirectory in [configs](configs), following the format of the existing ones.
