# order : 订单表
id n ++
user_id n @fk(user.id)
total d
status s @in(draft,pending,done)

# user : 用户表
id n ++
name s
