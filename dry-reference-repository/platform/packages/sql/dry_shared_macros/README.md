# SQL template macro package: `dry_shared_macros`

This is an example of a **buildable, versioned** SQL macro package.

How reuse happens:
- The package is versioned (git tag or internal registry).
- Domain repositories declare it as a dependency in their package manifest.
- Teams call macros by namespace instead of copying SQL fragments.

The package is intentionally runtime-neutral. A real organization could publish the same
concept through its chosen SQL compiler or SQL templating runtime.