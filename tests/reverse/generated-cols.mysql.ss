$ generated_cols

# products
id n ++
name *
price n *
qty n * =1
total n AS (price * qty) VIRTUAL
tax n AS (price * 0.1) STORED
