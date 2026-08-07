from sqlalchemy import (Integer, String, Numeric, ForeignKey)
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

# Test
class FK(Base):
    __tablename__ = 'FK'


class users(Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(32), nullable=False)

class orders(Base):
    __tablename__ = 'orders'

    id = Column(Integer, primary_key=True, autoincrement=True)
    amount = Column(Numeric(precision=16, scale=2), nullable=False)
