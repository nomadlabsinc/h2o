# Crystal Performance Checklist (from official guide)

Based on https://crystal-lang.org/reference/1.16/guides/performance.html

- [ ] **Profile before optimizing:** Always profile your Crystal applications with the `--release` flag to identify actual bottlenecks before attempting optimizations. Avoid premature optimization.
- [ ] **Avoiding Memory Allocations:**
    - [ ] Prefer `struct` over `class` when possible, as `struct` uses stack memory (no heap allocation).
    - [ ] Avoid creating intermediate strings when writing to an IO. Override `to_s(io)` instead of `to_s` for custom types.
    - [ ] Use string interpolation (`"Hello, #{name}"`) instead of concatenation (`"Hello, " + name.to_s`).
    - [ ] Use `String.build` for string building to avoid `IO::Memory` allocation.
    - [ ] Avoid creating temporary objects over and over in loops. Use tuples or pre-allocate arrays/hashes outside loops.
- [ ] **Iterating Strings:**
    - [ ] Avoid `string[i]` for iterating strings due to UTF-8 encoding and O(n^2) complexity.
    - [ ] Use iteration methods like `each_char`, `each_byte`, `each_codepoint`, or `Char::Reader` for efficient string iteration.

## Specific Recommendations for `h2o`

Based on an initial review of the `h2o` codebase and the Crystal Performance Guide:

- [ ] **Optimize Header Name Lowercasing:** In `H2O::Connection#build_request_headers`, the `name.downcase` operation for each header can lead to multiple temporary string allocations. Consider pre-processing common header names or exploring alternative strategies to avoid repeated string creation in hot paths.
- [ ] **Optimize StreamPool Iterations:** The `H2O::StreamPool#active_streams` and `H2O::StreamPool#closed_streams` methods currently create new `Array` objects and iterate over all streams on each invocation. If these methods are called frequently, consider optimizing them to avoid repeated temporary array allocations, perhaps by maintaining separate collections or using a more efficient filtering mechanism.
