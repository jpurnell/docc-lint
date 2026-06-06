# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.0.0] - 2026-06-05

### Added
- Initial release of docc-lint CLI tool for DocC documentation validation
- DocC catalog scanning with configurable ignore patterns
- Multiple processing strategies: batch, binary search, file-by-file
- Output formats: terminal, JSON, CSV, SARIF
- Task group reference validation rule
- File hash caching for incremental linting
- Symbol graph generation for documentation coverage analysis
- Markdown linting for standalone documentation files
- Documentation comments on all public APIs
- os.Logger integration with privacy annotations

### Fixed
- Process pipe read ordering to prevent deadlocks
- Force unwraps replaced with safe optional handling
- C-style format strings replaced with Swift string interpolation
- Path validation for FileManager operations
- Argument validation for Process invocations
