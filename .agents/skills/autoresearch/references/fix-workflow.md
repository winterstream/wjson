# Fix Workflow (`/autoresearch:fix`)

The `fix` workflow is a lightweight version of the `debug` loop. It is designed for situations where you have a specific, known failure (e.g., a TypeScript error or a lint violation) and you want to fix it without the overhead of full reproduction and isolation.

## Protocol

### 1. Context Loading
*   Read the error message or description provided in the command.
*   Identify the affected file(s).
*   Read the current state of those files.

### 2. Hypothesis
*   Form a direct hypothesis on how to fix the specific error.
*   The fix must be minimal and targeted.

### 3. Execution
*   Apply the fix.
*   Commit the change.

### 4. Verification
*   Run the command that triggered the original failure (e.g., `npx tsc` or `npm run lint`).
*   If a `Guard` is set in the main autoresearch config, run that as well.

### 5. Decision
*   If the error is gone and Guard passes: **KEEP**.
*   If the error persists: **RETRY** (max 3 times) with a different approach.
*   If it still fails after 3 tries: **REVERT** and report to the user.

## When to use `:fix` vs `:debug`
*   Use **`:fix`** for mechanical errors: "Fix the lint error on line 42", "Fix the missing import in `utils.ts`".
*   Use **`:debug`** for logical errors: "The login flow fails for users with specialized characters", "Database connection timeouts under high load".
