# docc-lint

A command-line tool for validating DocC documentation and reporting issues with accurate source locations.

## Overview

`docc-lint` scans your Swift package's DocC documentation catalogs and reports warnings and errors with precise file, line, and column information. It integrates with CI/CD pipelines and supports multiple output formats including terminal, JSON, CSV, and SARIF.

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/docc-lint", from: "1.0.0")
]
```

### Build from Source

```bash
git clone https://github.com/yourusername/docc-lint.git
cd docc-lint
swift build --configuration release
```

The binary will be at `.build/release/docc-lint`.

## Usage

### Basic Usage

```bash
# Lint the current directory (syntax-only mode, fast)
docc-lint lint

# Full validation with symbol graph support (slower, more comprehensive)
docc-lint lint --full

# Lint a specific project directory
docc-lint lint /path/to/your/project --full
```

### Output Formats

```bash
# Terminal output (default)
docc-lint lint --full

# JSON output
docc-lint lint --full --format json

# CSV output
docc-lint lint --full --format csv

# SARIF output (for IDE/CI integration)
docc-lint lint --full --format sarif

# Write to file
docc-lint lint --full --format json --output results.json
```

### CI/CD Integration

```bash
# Treat warnings as errors (exit code 2)
docc-lint lint --full --strict

# GitHub Actions annotations
docc-lint lint --full --github-actions

# Combine with output file
docc-lint lint --full --format sarif --output docc-results.sarif --strict
```

### Caching

docc-lint caches results to speed up subsequent runs:

```bash
# Disable caching (always rescan all files)
docc-lint lint --full --no-cache

# Clear cache before running
docc-lint lint --full --clear-cache

# Use custom cache location
docc-lint lint --full --cache-path /path/to/cache
```

### Filtering

```bash
# Minimum severity to report
docc-lint lint --full --severity warning  # warning (default), error, note

# Ignore specific patterns
docc-lint lint --full --ignore "**/*Tests*" --ignore "**/Fixtures/*"

# Include Swift doc comments (/// comments)
docc-lint lint --full --include-swift-docs
```

### Verbosity

```bash
# Verbose output with timing information
docc-lint lint --full --verbose

# Quiet mode (only errors)
docc-lint lint --full --quiet
```

## Validation Modes

### Syntax-Only Mode (Default)

Fast validation that doesn't require building symbol graphs:

```bash
docc-lint lint
```

**Best for:**
- Quick feedback during development
- Pre-commit hooks
- Large codebases where full validation is slow

### Full Mode

Comprehensive validation with symbol graph support:

```bash
docc-lint lint --full
```

**Best for:**
- CI/CD pipelines
- Pre-release validation
- Detecting unresolved symbol references

**Note:** Full mode requires that your package can be built. It generates symbol graphs to resolve symbol references in documentation.

## Example Output

### Terminal Output

```
DocC Lint Results
=================

1.1-GettingStarted.md
   Line 59, Column 1-55
   │
 59 │ let ts = TimeSeries(periods: periods, values: revenue)
      │ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      │
   warning: Only links are allowed in task group list items

   Suggested fix: Remove non-link item
      - let ts = TimeSeries(periods: periods, values: revenue)
      (remove this line)

──────────────────────────────────────────────────

Summary: 67 files scanned, 1 warning
Scan duration: 7.02s
```

### JSON Output

```json
{
  "version": "1.0.0",
  "timestamp": "2026-03-12T10:30:00Z",
  "summary": {
    "filesScanned": 67,
    "filesWithIssues": 1,
    "totalErrors": 0,
    "totalWarnings": 1,
    "totalNotes": 0,
    "scanDuration": 7.02
  },
  "diagnostics": [
    {
      "file": "/path/to/1.1-GettingStarted.md",
      "line": 59,
      "column": 1,
      "endColumn": 55,
      "severity": "warning",
      "message": "Only links are allowed in task group list items",
      "content": "let ts = TimeSeries(periods: periods, values: revenue)",
      "ruleId": "task-group-links-only",
      "suggestedFix": {
        "description": "Remove non-link item",
        "replacement": ""
      }
    }
  ]
}
```

## Common Warnings and Fixes

### "Only links are allowed in task group list items"

This warning occurs when DocC's parser interprets bullet points (`-`) as task group items when they're not inside a `## Topics` section.

**Problem:** Using `-` bullets in article content can trigger task-group parsing.

**Solutions:**

1. Use Unicode bullets instead:
   ```markdown
   • Feature one
   • Feature two
   ```

2. Use bold labels with em-dash:
   ```markdown
   **Feature One** - Description here.
   **Feature Two** - Another description.
   ```

3. Use paragraphs:
   ```markdown
   Feature One does X. Feature Two does Y.
   ```

### Unresolved Symbol References

Warnings like `'Symbol' doesn't exist at '/Path'` indicate broken symbol links.

**Solutions:**

1. Verify the symbol exists and is public
2. Check spelling and case sensitivity
3. Use the full symbol path: `````Package/Module/Type/method(_:)```

## GitHub Actions Integration

```yaml
name: Documentation Lint

on: [push, pull_request]

jobs:
  lint-docs:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build docc-lint
        run: |
          git clone https://github.com/yourusername/docc-lint.git /tmp/docc-lint
          cd /tmp/docc-lint
          swift build --configuration release

      - name: Lint Documentation
        run: |
          /tmp/docc-lint/.build/release/docc-lint lint --full \
            --format sarif \
            --output docc-results.sarif \
            --github-actions

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: docc-results.sarif
```

## Architecture

docc-lint uses several processing strategies:

**CatalogProcessor:** Processes entire DocC catalogs for accurate warnings without false positives from cross-reference resolution.

**BinarySearchProcessor:** Efficiently locates which files contain issues using a divide-and-conquer approach.

**HashCache:** Caches file hashes and scan results to skip unchanged files on subsequent runs.

## Requirements

- Swift 6.0+
- macOS 14+ or Linux
- Xcode Command Line Tools (for `docc` on macOS)

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Related Resources

- [Apple DocC Documentation](https://www.swift.org/documentation/docc/)
- [DocC Reference](https://developer.apple.com/documentation/docc)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
