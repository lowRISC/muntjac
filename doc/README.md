# Muntjac

Muntjac is a minimal 64-bit RISC-V multicore processor that's easy to understand, verify, and extend. The focus is on having a clean, well-tested design which others can build upon and further customise. Performance is secondary to correctness, but the aim is to work towards a design point (in terms of PPA) that maximises the value of Muntjac as a baseline design for educational, academic, or real-world use.

# Components

 * Front-end (instruction fetch)
 * Back-end (decode, execute, memory access, write back)
 * Caches

# Interfaces

 * [Pipeline <-> instruction cache](pipeline_icache_intf.md)
 * [Pipeline <-> data cache](pipeline_dcache_intf.md)
 * [Front-end <-> back-end](frontend_backend_intf.md)
