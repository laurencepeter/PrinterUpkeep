export class AppError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
    public readonly code?: string,
  ) {
    super(message);
  }
}

export class NotFoundError extends AppError {
  constructor(entity: string) {
    super(404, `${entity} not found`, 'not_found');
  }
}

export class ValidationError extends AppError {
  constructor(message: string) {
    super(400, message, 'validation_error');
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super(409, message, 'conflict');
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'Authentication required') {
    super(401, message, 'unauthorized');
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Insufficient permissions') {
    super(403, message, 'forbidden');
  }
}
