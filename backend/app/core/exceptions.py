from typing import Any, Dict, Optional


class BaseAppException(Exception):
    def __init__(
        self,
        message: str,
        status_code: int = 400,
        data: Optional[Dict[str, Any]] = None,
    ):
        self.message = message
        self.status_code = status_code
        self.data = data or {}
        super().__init__(self.message)


class NotFoundException(BaseAppException):
    def __init__(self, message: str = "Resource not found", data: Optional[Dict[str, Any]] = None):
        super().__init__(message=message, status_code=404, data=data)


class AuthException(BaseAppException):
    def __init__(self, message: str = "Authentication failed", data: Optional[Dict[str, Any]] = None):
        super().__init__(message=message, status_code=401, data=data)


class ForbiddenException(BaseAppException):
    def __init__(self, message: str = "Access denied", data: Optional[Dict[str, Any]] = None):
        super().__init__(message=message, status_code=403, data=data)


class ConflictException(BaseAppException):
    def __init__(self, message: str = "Resource conflict", data: Optional[Dict[str, Any]] = None):
        super().__init__(message=message, status_code=409, data=data)


class ValidationException(BaseAppException):
    def __init__(self, message: str = "Invalid input data", data: Optional[Dict[str, Any]] = None):
        super().__init__(message=message, status_code=422, data=data)
