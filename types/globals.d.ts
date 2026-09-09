/** The console handle app.js exposes for poking at the app by hand. */
declare global {
  interface Window {
    now: { poll(): Promise<void>; preview(n?: number): void };
  }
}
export {};
