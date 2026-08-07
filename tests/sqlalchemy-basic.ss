# SQLAlchemy Basic Test

$ myapp

# users
id n++
name s32
email s128

# orders
id n++
user_id > users.id
amount m
