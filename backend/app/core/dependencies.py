from typing import Any, Optional
import jwt
from fastapi import Depends, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.config import settings
from app.core.constants import UserRole
from app.core.exceptions import AuthException, ForbiddenException
from app.core.security import decode_token
from app.database.session import get_db
from app.models.user import Admin, Faculty

security_scheme = HTTPBearer(auto_error=False)


async def get_token_payload(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_scheme)) -> dict:
    if not credentials:
        raise AuthException("Missing authorization bearer token header.")
    try:
        payload = decode_token(credentials.credentials)
        return payload
    except jwt.PyJWTError as e:
        raise AuthException(f"Invalid authentication token: {e}")


async def get_current_user(payload: dict = Depends(get_token_payload), db: AsyncSession = Depends(get_db)) -> Any:
    user_id = payload.get("sub")
    role = payload.get("role")
    if not user_id or not role:
        raise AuthException("Malformed authentication token credentials.")

    if role == UserRole.ADMIN.value:
        stmt = select(Admin).where(Admin.id == user_id)
        res = await db.execute(stmt)
        user = res.scalars().first()
        if user:
            return user
    elif role == UserRole.FACULTY.value:
        stmt = select(Faculty).where(Faculty.id == user_id)
        res = await db.execute(stmt)
        user = res.scalars().first()
        if user:
            return user

    raise AuthException("Account not found or invalid token details.")


class RoleChecker:
    def __init__(self, allowed_roles: list):
        self.allowed_roles = allowed_roles

    def __call__(self, payload: dict = Depends(get_token_payload)) -> None:
        role = payload.get("role")
        if role not in self.allowed_roles:
            raise ForbiddenException("Access denied. You do not possess the required permission permissions.")


def require_role(roles: list) -> RoleChecker:
    return RoleChecker(roles)
