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
