import { formatGreeting } from "test-package";

// Trivial entrypoint — just exercises the workspace import.
function main(): void {
  console.log(formatGreeting("world"));
}

main();
