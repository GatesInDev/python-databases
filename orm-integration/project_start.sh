#!/usr/bin/env bash

set -euo pipefail

PROJECT="python-databases"

echo "Creating project: $PROJECT"

# Avoid overwriting an existing project.
if [ -e "$PROJECT" ]; then
    echo "Error: '$PROJECT' already exists."
    echo "Rename or remove the existing directory before continuing."
    exit 1
fi

# --------------------------------------------------
# 1. Create directories
# --------------------------------------------------

mkdir -p "$PROJECT"/app/domain
mkdir -p "$PROJECT"/app/repositories
mkdir -p "$PROJECT"/app/services
mkdir -p "$PROJECT"/tests

cd "$PROJECT"

# --------------------------------------------------
# 2. Create Python package files
# --------------------------------------------------

touch app/__init__.py
touch app/domain/__init__.py
touch app/repositories/__init__.py
touch app/services/__init__.py

# --------------------------------------------------
# 3. requirements.txt
# --------------------------------------------------

cat > requirements.txt <<'EOF'
redis>=5.0
pymongo>=4.6
python-dotenv>=1.0
pytest>=8.0
EOF

# --------------------------------------------------
# 4. .env
# --------------------------------------------------

cat > .env <<'EOF'
MONGODB_URI=mongodb://localhost:27017/
MONGODB_DATABASE=mydatabase

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_TTL_SECONDS=300
EOF

# --------------------------------------------------
# 5. .gitignore
# --------------------------------------------------

cat > .gitignore <<'EOF'
.env
.venv/
venv/
__pycache__/
*.py[cod]
.pytest_cache/
.coverage
EOF

# --------------------------------------------------
# 6. Domain model
# --------------------------------------------------

cat > app/domain/user.py <<'PY'
from dataclasses import asdict, dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class User:
    id: str
    name: str
    email: str

    def to_dict(self) -> dict[str, str]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "User":
        return cls(
            id=str(data["id"]),
            name=str(data["name"]),
            email=str(data["email"]),
        )
PY

# --------------------------------------------------
# 7. Configuration
# --------------------------------------------------

cat > app/config.py <<'PY'
import os
from dataclasses import dataclass

from dotenv import load_dotenv


load_dotenv()


@dataclass(frozen=True, slots=True)
class Settings:
    mongodb_uri: str
    mongodb_database: str
    redis_host: str
    redis_port: int
    redis_db: int
    redis_ttl_seconds: int

    @classmethod
    def from_env(cls) -> "Settings":
        settings = cls(
            mongodb_uri=os.getenv(
                "MONGODB_URI",
                "mongodb://localhost:27017/",
            ),
            mongodb_database=os.getenv(
                "MONGODB_DATABASE",
                "mydatabase",
            ),
            redis_host=os.getenv("REDIS_HOST", "localhost"),
            redis_port=int(os.getenv("REDIS_PORT", "6379")),
            redis_db=int(os.getenv("REDIS_DB", "0")),
            redis_ttl_seconds=int(
                os.getenv("REDIS_TTL_SECONDS", "300")
            ),
        )

        if settings.redis_ttl_seconds <= 0:
            raise ValueError("Redis TTL must be positive.")

        return settings
PY

# --------------------------------------------------
# 8. Repository interface
# --------------------------------------------------

cat > app/repositories/user_repository.py <<'PY'
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
PY

# --------------------------------------------------
# 9. MongoDB repository
# --------------------------------------------------

cat > app/repositories/mongodb_user_repository.py <<'PY'
from pymongo import ASCENDING
from pymongo.collection import Collection

from app.domain.user import User
from app.repositories.user_repository import UserRepository


class MongoDBUserRepository(UserRepository):
    def __init__(self, collection: Collection):
        self._collection = collection

        self._collection.create_index(
            [("email", ASCENDING)],
            unique=True,
        )

    def get_by_id(self, user_id: str) -> User | None:
        document = self._collection.find_one({"_id": user_id})

        if document is None:
            return None

        return self._document_to_user(document)

    def save(self, user: User) -> User:
        document = {
            "_id": user.id,
            "name": user.name,
            "email": user.email,
        }

        self._collection.replace_one(
            {"_id": user.id},
            document,
            upsert=True,
        )

        return user

    def delete(self, user_id: str) -> bool:
        result = self._collection.delete_one({"_id": user_id})
        return result.deleted_count > 0

    @staticmethod
    def _document_to_user(document: dict) -> User:
        return User(
            id=str(document["_id"]),
            name=document["name"],
            email=document["email"],
        )
PY

# --------------------------------------------------
# 10. Redis caching repository
# --------------------------------------------------

cat > app/repositories/cached_user_repository.py <<'PY'
import json

import redis
from redis.exceptions import RedisError

from app.domain.user import User
from app.repositories.user_repository import UserRepository


class CachedUserRepository(UserRepository):
    CACHE_PREFIX = "user:"

    def __init__(
        self,
        repository: UserRepository,
        cache: redis.Redis,
        ttl_seconds: int = 300,
    ):
        if ttl_seconds <= 0:
            raise ValueError("TTL must be positive.")

        self._repository = repository
        self._cache = cache
        self._ttl_seconds = ttl_seconds

    def get_by_id(self, user_id: str) -> User | None:
        cache_key = self._cache_key(user_id)

        try:
            cached_data = self._cache.get(cache_key)

            if cached_data is not None:
                return User.from_dict(json.loads(cached_data))

        except (RedisError, ValueError, TypeError):
            # Fall back to MongoDB if Redis is unavailable
            # or the cached data is invalid.
            pass

        user = self._repository.get_by_id(user_id)

        if user is not None:
            self._set_cache(cache_key, user)

        return user

    def save(self, user: User) -> User:
        saved_user = self._repository.save(user)
        self._delete_cache(user.id)
        return saved_user

    def delete(self, user_id: str) -> bool:
        deleted = self._repository.delete(user_id)
        self._delete_cache(user_id)
        return deleted

    def _set_cache(self, key: str, user: User) -> None:
        try:
            self._cache.set(
                key,
                json.dumps(user.to_dict()),
                ex=self._ttl_seconds,
            )
        except RedisError:
            pass

    def _delete_cache(self, user_id: str) -> None:
        try:
            self._cache.delete(self._cache_key(user_id))
        except RedisError:
            pass

    @classmethod
    def _cache_key(cls, user_id: str) -> str:
        return f"{cls.CACHE_PREFIX}{user_id}"
PY

# --------------------------------------------------
# 11. User service
# --------------------------------------------------

cat > app/services/user_service.py <<'PY'
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
PY

# --------------------------------------------------
# 12. Main application
# --------------------------------------------------

cat > app/main.py <<'PY'
import logging

import redis
from pymongo import MongoClient

from app.config import Settings
from app.repositories.cached_user_repository import CachedUserRepository
from app.repositories.mongodb_user_repository import MongoDBUserRepository
from app.services.user_service import UserService


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main() -> None:
    settings = Settings.from_env()

    mongo_client = MongoClient(
        settings.mongodb_uri,
        serverSelectionTimeoutMS=5000,
    )

    redis_client = redis.Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        db=settings.redis_db,
        decode_responses=True,
        socket_connect_timeout=3,
        socket_timeout=3,
    )

    try:
        mongo_client.admin.command("ping")
        redis_client.ping()

        logger.info("MongoDB and Redis are connected.")

        database = mongo_client[settings.mongodb_database]

        mongo_repository = MongoDBUserRepository(
            database["users"]
        )

        user_repository = CachedUserRepository(
            repository=mongo_repository,
            cache=redis_client,
            ttl_seconds=settings.redis_ttl_seconds,
        )

        user_service = UserService(user_repository)

        user = user_service.create_user(
            name="John Doe",
            email="john@example.com",
        )

        logger.info("Created user: %s", user)

        first_read = user_service.get_user(user.id)
        logger.info("First read: %s", first_read)

        second_read = user_service.get_user(user.id)
        logger.info("Second read: %s", second_read)

    finally:
        redis_client.close()
        mongo_client.close()


if __name__ == "__main__":
    main()
PY

# --------------------------------------------------
# 13. Unit tests
# --------------------------------------------------

cat > tests/test_user_service.py <<'PY'
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
PY

# --------------------------------------------------
# 14. Create a local virtual environment
# --------------------------------------------------

echo
echo "Creating Python virtual environment..."

python3 -m venv .venv

echo
echo "Installing Python dependencies..."

if ! .venv/bin/python -m pip install -r requirements.txt; then
    echo "Warning: Dependency installation failed."
    echo "You can retry later with:"
    echo "  cd $PROJECT"
    echo "  source .venv/bin/activate"
    echo "  python -m pip install -r requirements.txt"
fi

# --------------------------------------------------
# 15. Display project tree
# --------------------------------------------------

echo
echo "Project created successfully!"
echo
echo "Project structure:"
find . -type f \
    -not -path "./.venv/*" \
    -not -path "./.git/*" \
    | sort

echo
echo "Next steps:"
echo "  cd $PROJECT"
echo "  source .venv/bin/activate"
echo "  python -m pytest -v"
echo "  python -m app.main"
echo
echo "Make sure Redis and MongoDB servers are running before starting the application."
