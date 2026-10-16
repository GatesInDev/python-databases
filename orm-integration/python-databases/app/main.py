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
