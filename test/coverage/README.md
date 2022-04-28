# Coverage

Coverage is a useful way of tracking how well a design has been tested. It works by defining a set of *coverpoints*, and counting how many of them are reached during testing.

Verilator provides us with *line coverage*, where each significant line of SystemVerilog is tracked. We can also define our own *functional coverage* by specifying particular states which we would like to see. See the [TileLink testing](../tilelink) for an example of functional coverage.

Neither of these approaches is perfect: it is possible to execute every line of code while producing an incorrect result, and functional coverage is only as useful as the set of coverpoints we define.

To generate a coverage report for the Muntjac core across a range of test binaries, use:

```
make coverage TESTS="test1 test2 test3"
```

This will produce a report which looks like:

```
ip/pipeline line coverage: 2099/2250 (93%)
ip/core line coverage:     2568/2861 (90%)
ip/fpu line coverage:      483/504 (96%)
```

You can see which coverpoints were reached by inspecting the annotated source files in the `coverage` directory. Each line containing a coverpoint will be prefixed with a number indicating how many times that line was reached during testing.
