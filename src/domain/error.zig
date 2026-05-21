const std = @import("std");

pub const DomainError = error{
    NotFound,
    NotAuthorized,
    AlreadyExists,
    InvalidOperation,
    Conflict,
    ValidationError,
};

pub const AuthError = error{
    InvalidCredentials,
    TokenExpired,
    TokenInvalid,
} || DomainError;

pub const StorageError = error{
    DatabaseError,
    SerializationError,
} || DomainError;
