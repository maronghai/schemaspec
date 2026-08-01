# customers
id n ! *
name s100 *
email s255

# orders
id n ++ *
customer_id *
total 10,2 =0
status s20 =pending

> customer_id customers.id
