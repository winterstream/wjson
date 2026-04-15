# /autoresearch:debug — Autonomous Debug Loop

This workflow is triggered by the `/autoresearch:debug` subcommand. It is designed to reproduce, isolate, and fix specific bugs autonomously.

## Context
Use this when something is clearly broken (e.g., a failing test, a crash, or a UI bug).

## Phase 1: Reproduction
1. Create a minimal reproduction script (e.g., `debug/repro.js` or a new test case).
2. Run the repro script and verify it fails as expected.
3. This repro command becomes your `Verify` command for the loop.

## Phase 2: Isolation
1. Use `grep` and `view_file` to find the code responsible for the failure.
2. Form a hypothesis about the root cause.

## Phase 3: Fix Loop
1. Start a standard autoresearch loop with:
   - **Goal**: Fix the bug identified in the repro script.
   - **Verify**: The repro command (must exit 0 on success).
   - **Guard**: Existing test suite and linting.

## Phase 4: Hardening
1. After the fix is verified, add a permanent regression test to the codebase.
2. Verify that the fix holds across the entire project.
