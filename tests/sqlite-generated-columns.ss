$ sqlite_generated_columns

# products

id      n++
name    s
price   n
qty     n
total   n  AS (price * qty) VIRTUAL
tax     n  AS (price * 0.1) STORED
