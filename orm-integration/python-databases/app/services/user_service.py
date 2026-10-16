from uuid import uuid4

from app.domain.user import User
from app.repositories.user_repository import UserRepository


class UserService:
    def __init__(self, repository: UserRepository):
        self._repository = repository

    def create_user(self, name: str, email: str) -> User:
        name = name.strip()
        email = email.strip().lower()

        if not name:
            raise ValueError("Name cannot be empty.")

        if not email or "@" not in email:
            raise ValueError("A valid email address is required.")

        user = User(
            id=str(uuid4()),
            name=name,
            email=email,
        )

        return self._repository.save(user)

    def get_user(self, user_id: str) -> User | None:
        if not user_id.strip():
            raise ValueError("User ID cannot be empty.")

        return self._repository.get_by_id(user_id)

    def delete_user(self, user_id: str) -> bool:
        if not user_id.strip():
            raise ValueError("User ID cannot be empty.")

        return self._repository.delete(user_id)
