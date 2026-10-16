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
