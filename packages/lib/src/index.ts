// Trivial pure formatter — no real logic. Exists to give the app something
// to import across the workspace boundary.
export function formatGreeting(name: string): string {
  return `Hello, ${name}!`;
}
