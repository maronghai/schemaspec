$ generated_cols

# products
id int ++ -- [score:50]
name *
price int * -- [score:50]
qty int * =1 -- [score:50]
total int AS (price * qty) VIRTUAL -- [score:50]
tax int AS (price * 0.1) STORED -- [score:50]
