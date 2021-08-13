# TileLink verification
A collection of tools used to test and verify Muntjac's TileLink IP.

For each of the TileLink protocol variants (TL-UL, TL-UH, TL-C), we provide:
 * A module which monitors a TileLink channel and checks that all communication adheres to the TileLink specification.
 * A collection of functional coverage groups, enumerating all of the states we want to see when testing.

All code targets [TileLink 1.8](https://sifive.cdn.prismic.io/sifive/7bef6f5c-ed3a-4712-866a-1a2e0c6b7b13_tilelink_spec_1.8.1.pdf).

To enable assertions, pass the `assertions_on` flag during the build process, for example:

```
make sim-core EXTRA_FLAGS=assertions_on
```

TODO: how to collect coverage information.

## Limitations
* Test modules assume that no TileLink signals are updated on the negative clock edge.
* Transactions involving the B channel are verified less rigorously. This is because the B channel allows too many outstanding requests to keep track of.

## Extending
To add new assertions, see [tl_assert.sv](tl_assert.sv).

To apply assertions to a new component, see [tl_checker.sv](tl_checker.sv) and [tl_bind.sv](tl_bind.sv).
