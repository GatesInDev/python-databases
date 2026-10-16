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
