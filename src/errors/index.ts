export class NotFounderError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NotFoundError";
  }
}
