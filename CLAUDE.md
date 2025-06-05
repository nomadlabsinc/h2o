# Claude Operating Instructions for Crystal Development

Adhere to these principles to ensure a high-quality, performant, and maintainable Crystal app:

1.  **Idiomatic Crystal:**
    *   Follow Crystal's [Coding Style Guide](https://crystal-lang.org/reference/1.16/conventions/coding_style.html) rigorously (e.g., `snake_case` for methods/variables, `PascalCase` for classes/modules, `SCREAMING_SNAKE_CASE` for constants).
    *   Leverage Crystal's concurrency primitives (`Channel`, `Fiber`, `Mutex`) appropriately.
    *   Prioritize type safety; use explicit type annotations where beneficial for clarity or performance, especially in performance-critical paths or public APIs.
    *   Employ `raise` for exceptional conditions and `begin...rescue` for robust error handling.

2.  **Performance Focus:**
    *   Consult Crystal's [Performance Guide](https://crystal-lang.org/reference/1.16/guides/performance.html).
    *   Minimize allocations, especially in hot loops (e.g., frame parsing/serialization, HPACK operations). Reuse buffers where possible.
    *   Optimize byte manipulation: use `IO#read_bytes` and `IO#write_bytes` efficiently. Avoid unnecessary `String` conversions in binary protocols.
    *   Profile frequently using `crystal build --release --no-debug` and tools like `perf` to identify bottlenecks.
    *   Be mindful of fiber context switching overhead; ensure fibers are used strategically for concurrency, not for trivial tasks.
    *   Connection pooling (as noted in development tasks) is a critical performance optimization to minimize TLS handshake and connection overhead.

4.  **Test-Driven Development (TDD):**
    *   Write tests *before* or concurrently with implementation.
    *   Ensure high unit test coverage for all components.
    *   Develop robust integration tests against real and mock servers.

5.  **Observability & Debugging:**
    *   Integrate Crystal's `Log` module for structured logging. Define log levels (e.g., `DEBUG`, `INFO`, `WARN`, `ERROR`) and allow configuration via environment variables (e.g., `LOG_LEVEL`).
    *   Utilize `crystal run --runtime-trace` (refer to [Runtime Tracing](https://crystal-lang.org/reference/1.16/guides/runtime_tracing.html)) for debugging concurrency issues.
    *   `tshark` or `Wireshark` are invaluable for inspecting raw TLS and HTTP/2 traffic.

6.  **Security Considerations:**
    *   Ensure proper certificate validation (trust store, SNI). Consider options for custom CA certificates or certificate pinning if required by the application's security posture.
    *   Protect against common HTTP/2 denial-of-service vectors (e.g., `SETTINGS` flood, `PRIORITY` flood, oversized frames).

## 🚨 CRITICAL: Code Quality and Formatting Standards

### Pre-Commit Checklist (MANDATORY)
Before ANY commit, Claude MUST:
1. **Run `crystal tool format`** - Format all Crystal code
2. **Run `crystal tool format --check`** - Verify formatting is correct
3. **Verify trailing newlines** - All files must end with a newline (POSIX compliance)
4. **Check trailing whitespace** - No trailing whitespace allowed
5. **Run `crystal spec`** - Ensure all tests pass

## 📋 Crystal Code Standards

### File Formatting Requirements
- **MUST run `crystal tool format`** before every commit
- **MUST have trailing newlines** on all files for POSIX compliance
- **NO trailing whitespace** - Remove all trailing spaces/tabs
- **Line endings**: Unix-style LF
- **Indentation**: Crystal standard (2 spaces)
- **Maximum line length**: 120 characters

### Type System Requirements
- **ALWAYS prefer explicit types over implicit types**
- **Use type annotations** for all method parameters and return values
- **Use type aliases** to simplify complex method signatures
- **Define clear type aliases** for commonly used complex types

```crystal
# ✅ GOOD: Explicit types with type alias
alias UserData = Hash(String, String | Int32 | Nil)

def process_user(data : UserData) : User
  # implementation
end

# ❌ BAD: Implicit types
def process_user(data)
  # implementation
end
```

### Method Design Guidelines
- **Target 5 lines or less** for most methods
- **Maximum 10 lines** for complex methods (rare exceptions allowed)
- **Extract helper methods** to maintain small method sizes
- **Single Responsibility Principle** - Each method does one thing

```crystal
# ✅ GOOD: Short, focused methods
def calculate_total(items : Array(Item)) : Float64
  validate_items(items)
  sum_prices(items) + calculate_tax(items)
end

private def validate_items(items : Array(Item)) : Nil
  raise ArgumentError.new("Empty items") if items.empty?
end

private def sum_prices(items : Array(Item)) : Float64
  items.sum(&.price)
end
```

### Class Design Guidelines
- **Target 100 lines or less** per class
- **Use modules** to separate concerns
- **Extract service objects** for complex operations
- **Prefer composition over inheritance**

### Ordering Conventions

#### Method Arguments
- **ALWAYS alphabetize arguments** when possible
- **Exception**: Logical grouping takes precedence (e.g., x, y, z coordinates)

```crystal
# ✅ GOOD: Alphabetized arguments
def create_user(
  email : String,
  name : String,
  password : String,
  role : String
) : User
  # implementation
end

# ❌ BAD: Random argument order
def create_user(
  name : String,
  password : String,
  email : String,
  role : String
) : User
  # implementation
end
```

#### Hash and Named Arguments
- **ALWAYS alphabetize hash keys**
- **ALWAYS alphabetize named arguments**

```crystal
# ✅ GOOD: Alphabetized hash keys
config = {
  api_key: "secret",
  host: "localhost",
  port: 3000,
  timeout: 30
}

# ✅ GOOD: Alphabetized named arguments
Client.new(
  api_key: key,
  base_url: url,
  timeout: 30,
  verify_ssl: true
)
```

#### Imports and Requires
- **Alphabetize within logical groups**
- **Group by**: stdlib, shards, local files

```crystal
# ✅ GOOD: Organized and alphabetized imports
# Standard library
require "http"
require "json"
require "uri"

# External shards
require "kemal"
require "pg"

# Local files
require "./config"
require "./models/*"
require "./services/*"
```

## 🛠️ Type Aliases Best Practices

### When to Use Type Aliases
- Complex union types
- Frequently used type combinations
- Improving method signature readability
- Domain-specific types

```crystal
# ✅ GOOD: Clear type aliases
alias JsonValue = String | Int32 | Float64 | Bool | Nil
alias Headers = Hash(String, String)
alias QueryParams = Hash(String, String | Array(String))
alias Callback = Proc(String, Nil)

class ApiClient
  def get(
    endpoint : String,
    headers : Headers = {} of String => String,
    params : QueryParams = {} of String => String | Array(String)
  ) : JsonValue
    # implementation
  end
end

# ❌ BAD: Repeated complex types
class ApiClient
  def get(
    endpoint : String,
    headers : Hash(String, String) = {} of String => String,
    params : Hash(String, String | Array(String)) = {} of String => String | Array(String)
  ) : String | Int32 | Float64 | Bool | Nil
    # implementation
  end
end
```

## 📏 Code Organization Patterns

### Module Structure
```crystal
module MyApp
  # Type aliases at the top
  alias ConfigHash = Hash(String, String | Int32 | Bool)

  # Constants next
  VERSION = "1.0.0"

  # Main class/module code
  class Application
    # Keep classes small and focused
  end
end
```

### Method Extraction Pattern
```crystal
# ❌ BAD: Long method
def process_order(order : Order) : ProcessedOrder
  # Validate order
  raise "Invalid order" unless order.valid?
  raise "No items" if order.items.empty?

  # Calculate totals
  subtotal = order.items.sum(&.price)
  tax = subtotal * 0.08
  shipping = calculate_shipping(order.items)
  total = subtotal + tax + shipping

  # Apply discounts
  if order.coupon
    discount = total * order.coupon.percentage
    total -= discount
  end

  # Create processed order
  ProcessedOrder.new(
    items: order.items,
    subtotal: subtotal,
    tax: tax,
    shipping: shipping,
    total: total
  )
end

# ✅ GOOD: Extracted methods
def process_order(order : Order) : ProcessedOrder
  validate_order(order)
  totals = calculate_totals(order)
  apply_discounts(totals, order.coupon)
  build_processed_order(order, totals)
end

private def validate_order(order : Order) : Nil
  raise InvalidOrderError.new unless order.valid?
  raise EmptyOrderError.new if order.items.empty?
end

private def calculate_totals(order : Order) : OrderTotals
  OrderTotals.new(
    subtotal: order.items.sum(&.price),
    tax: calculate_tax(order),
    shipping: calculate_shipping(order.items)
  )
end
```

## 🔧 Automated Formatting Commands

```bash
# Format all Crystal files
crystal tool format

# Check formatting without modifying
crystal tool format --check

# Remove trailing whitespace (using sed)
find . -name "*.cr" -type f -exec sed -i '' 's/[[:space:]]*$//' {} +

# Ensure trailing newlines
find . -name "*.cr" -type f -exec sh -c 'tail -c1 {} | read -r _ || echo >> {}' \;

# Combined pre-commit command
crystal tool format && find . -name "*.cr" -type f -exec sed -i '' 's/[[:space:]]*$//' {} + && find . -name "*.cr" -type f -exec sh -c 'tail -c1 {} | read -r _ || echo >> {}' \;
```

## 🔀 Git Workflow and GitHub Integration

### Branch Strategy (MANDATORY)
- **NEVER work directly on main branch** - Always create feature branches
- **ALWAYS submit Pull Requests** - Never push directly to main
- **Use descriptive branch names** - Follow pattern: `fix-`, `feature-`, `refactor-`, etc.

### GitHub Integration
- **Use `gh` CLI for all GitHub operations** when asked to interact with GitHub
- **Always create PRs through `gh pr create`** with proper titles and descriptions
- **Monitor GitHub Actions** until all workflow checks pass
- **Address any PR feedback** promptly and thoroughly

### Workflow Steps
1. **Create feature branch**: `git checkout -b feature-name`
2. **Make changes and commit**: Follow pre-commit checklist
3. **Push feature branch**: `git push -u origin feature-name`
4. **Create PR**: `gh pr create --title "Title" --body "Description"`
5. **Monitor workflows**: Ensure all GitHub Actions pass
6. **Address feedback**: Make changes if requested
7. **Merge only after approval**: Never merge your own PRs

### PR Requirements
- **Clear title** describing the change
- **Detailed description** with context and impact
- **Link to related issues** if applicable
- **Test coverage** for all changes
- **Documentation updates** when needed

## 📝 Additional Guidelines

### Naming Conventions
- **Classes/Modules**: PascalCase
- **Methods/Variables**: snake_case
- **Constants**: SCREAMING_SNAKE_CASE
- **Type aliases**: PascalCase

### Error Handling
- Use specific exception types
- Provide meaningful error messages
- Use `begin/rescue/ensure/end` blocks properly

### Safe Null Handling (CRITICAL)
- **NEVER use `.not_nil!`** - This is an unsafe pattern that can cause runtime crashes
- **Use safe alternatives instead**:
  - `.try(&.method)` for conditional method calls
  - `if value = nullable_var` for safe assignment
  - `.as(Type)` for guaranteed type casts (when type is known to be safe)
  - Explicit nil checks with proper error handling

```crystal
# ❌ DANGEROUS: Using .not_nil!
host = uri.host.not_nil!  # Can crash at runtime
fiber_alive = @fiber.not_nil!.dead?

# ✅ SAFE: Use proper null handling
host = uri.host || raise ArgumentError.new("Missing host")
fiber_alive = @fiber.try(&.dead?) == false

# ✅ SAFE: Safe assignment pattern
if response = @response
  response.status = 200
end

# ✅ SAFE: Type cast when guaranteed by prior validation
value = validated_value.as(String)  # Only when validation ensures non-nil
```

### Documentation
- Document public APIs
- Use Crystal's documentation format
- Include examples for complex methods

### Testing
- Write tests for all public methods
- Keep test methods small and focused
- Use descriptive test names
- **ALWAYS set timeouts such that integration tests time out within the code in 5s, rather than 2m**
  - Integration tests should use `timeout: 1.seconds` or similar short timeouts
  - This prevents CLI timeout issues and ensures fast feedback cycles
  - Example: `client = H2O::Client.new(timeout: 1.seconds)` instead of longer timeouts

## 🚀 Quick Reference

**Before EVERY commit:**
1. `crystal tool format`
2. Remove trailing whitespace
3. Ensure trailing newlines
4. Verify alphabetical ordering
5. Check method lengths (≤5 lines preferred, ≤10 lines max)
6. Check class lengths (≤100 lines)
7. Ensure explicit types everywhere
8. Use type aliases to shorten code where needed
9. Verify integration tests use 5s or shorter timeouts
10. Run tests

**Code Review Checklist:**
- [ ] All types are explicit
- [ ] Type aliases used for complex signatures
- [ ] Methods are 5 lines or less (10 max)
- [ ] Classes are 100 lines or less
- [ ] Arguments are alphabetized
- [ ] Hash keys are alphabetized
- [ ] Integration tests use 5s or shorter timeouts
- [ ] **NO `.not_nil!` usage** - Use safe alternatives
- [ ] Proper null handling with `.try()` or explicit checks
- [ ] No trailing whitespace
- [ ] All files have trailing newlines
- [ ] Code is properly formatted

---

This document should be updated whenever new patterns or conventions are established for the project.
