from sqlalchemy import (Integer, String, Numeric, ForeignKey)
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

# Test
class Basic(Base):
    __tablename__ = 'Basic'


class users(Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(32), nullable=False)
    email = Column(String(128), nullable=False)

class orders(Base):
    __tablename__ = 'orders'

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    amount = Column(Numeric(precision=16, scale=2), nullable=False)
