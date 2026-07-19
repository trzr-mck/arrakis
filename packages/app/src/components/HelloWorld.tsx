// CODEOWNERS test fixture — not real UI code.
// Exists only as a distinct file path targeted by a single-owner CODEOWNERS
// rule, to validate CODEOWNERS review enforcement in the branch-protection
// POC. No real logic.

export function HelloWorld(): string {
  return "Hello, world!";
}
