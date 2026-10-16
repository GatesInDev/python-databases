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
