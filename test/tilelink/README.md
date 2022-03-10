# TileLink verification
A collection of tools used to test and verify Muntjac's TileLink IP.

For each of the TileLink protocol variants (TL-UL, TL-UH, TL-C), we provide:
 * A module which monitors a TileLink channel and checks that all communication adheres to the TileLink specification.
 * A collection of functional coverage groups, enumerating all of the states we want to see when testing.

We also provide a random traffic generator to exercise as many states as possible.

All code targets [TileLink 1.8](https://sifive.cdn.prismic.io/sifive/7bef6f5c-ed3a-4712-866a-1a2e0c6b7b13_tilelink_spec_1.8.1.pdf).

Limitations:
* Test modules assume that no TileLink signals are updated on the negative clock edge.
* Transactions involving the B channel are verified less rigorously. This is because the B channel allows too many outstanding requests to keep track of.
* Muntjac's TileLink IP does not support forwarding of A messages to the B channel, or C messages to the D channel. None of this behaviour is supported by the verification tools either.

## Assertions

Assertions check compliance with the TileLink specification, ensuring that each message is self-consistent, that consecutive beats within a burst message are consistent with each other, and that responses are consistent with the requests that triggered them.

To enable assertions in a Muntjac simulator, pass the `assertions_on` flag during the build process, for example:

```
make sim-core EXTRA_FLAGS=assertions_on
```
 
Alternatively, a dedicated TileLink simulator can be generated which has assertions switched on by default (see below).

## Coverage

Coverage aims to quantify how much of the state space has been explored during testing.

To run a simple test and generate a coverage number, run `make`. This will produce an output along the lines of:

```
Total coverage (57/79) 72.00%
```

 * The length of simulation can be controlled using `make CYCLES=X`.
 * A different random seed can be selected using `make SEED=X`.

For more options, see below.

### Simulation
We offer simulation of an isolated TileLink network. This can be coupled with random traffic generation to exercise the network.

```
make sim
```

This generates `muntjac_tl` with the following command line options:

| Argument | Description |
| --- | --- |
| `--help` | Display usage information and exit |
| `--run X` | Generate random traffic for the given duration (in cycles) |
| `--random-seed X `| Set the random seed |
| `--coverage X` | Dump coverage information to file `X` |
| `--vcd/fst X` | Dump waveform output to a file. Only one format can be enabled at a time: see [`tl_tb.core`](./tl_tb.core) to change which one (requires simulator to be rebuilt). |
| `-v` | Display information about each message sent as simulation proceeds |

The default simulated network is a simple bus connecting three hosts (TL-C, TL-UH, TL-UL) to three devices (TL-C, TL-UH, TL-UL). To change this, update [`tl_wrapper.sv`](rtl/tl_wrapper.sv) and [`tl_harness.h`](src/tl_harness.h).

TODO: 
 * Add a TileLink network generator to simplify this process
 * Add more configuration options in the traffic generator

### Coverpoints

To see which coverpoints were reached during simulation, look through the `coverage` directory. This will contain copies of SystemVerilog source files, with annotations describing how many time each coverpoint was reached. "Next point on previous line" indicates that multiple coverpoints were on the same line of source code.

The default coverpoints are:

 * For the whole system
   * Messages were sent/received simultaneously by every combination of endpoints
 * For each endpoint (host, device):
   * Messages were sent/received simultaneously on every combination of channels
 * For each channel (`A`, `B`, `C`, `D`, `E`):
   * Two messages were sent with/without a pause between them
   * A valid message was/was not accepted by the recipient
   * The corrupt/denied bits were used (if appropriate)
 * For each field (e.g. `A.address`, `D.data`):
   * Consecutive messages used the same/different values
   * The value changed/stayed the same while waiting for a message to be accepted

## Limitations
 * Test modules assume that no TileLink signals are updated on the negative clock edge.
 * Transactions involving the B channel are verified less rigorously. This is because the B channel allows too many outstanding requests to keep track of.

## Extension
To add new assertions or coverpoints, see [`tl_assert.sv`](rtl/tl_assert.sv) and [`tl_cover.sv`](rtl/tl_cover.sv).

To apply assertions and coverage to a new component, see [`tl_checker.sv`](rtl/tl_checker.sv) and [`tl_bind.sv`](rtl/tl_bind.sv).
