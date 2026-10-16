import pytest

from app.domain.user import User
from app.repositories.user_repository import UserRepository
from app.services.user_service import UserService


class FakeUserRepository(UserRepository):
    def __init__(self):
        self.users: dict[str, User] = {}

    def get_by_id(self, user_id: str) -> User | None:
        return self.users.get(user_id)

    def save(self, user: User) -> User:
        self.users[user.id] = user
        return user

    def delete(self, user_id: str) -> bool:
        return self.users.pop(user_id, None) is not None


def test_create_and_get_user():
    service = UserService(FakeUserRepository())

    created = service.create_user(
        "John Doe",
        "JOHN@EXAMPLE.COM",
    )

    retrieved = service.get_user(created.id)

    assert retrieved == created
    assert retrieved.name == "John Doe"
    assert retrieved.email == "john@example.com"


def test_delete_user():
    service = UserService(FakeUserRepository())

    user = service.create_user(
        "John Doe",
        "john@example.com",
    )

    assert service.delete_user(user.id) is True
    assert service.get_user(user.id) is None


def test_reject_empty_name():
    service = UserService(FakeUserRepository())

    with pytest.raises(ValueError):
        service.create_user("", "john@example.com")
