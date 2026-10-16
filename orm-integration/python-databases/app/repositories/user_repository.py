from abc import ABC, abstractmethod

from app.domain.user import User


class UserRepository(ABC):
    @abstractmethod
    def get_by_id(self, user_id: str) -> User | None:
        raise NotImplementedError

    @abstractmethod
    def save(self, user: User) -> User:
        raise NotImplementedError

    @abstractmethod
    def delete(self, user_id: str) -> bool:
        raise NotImplementedError
