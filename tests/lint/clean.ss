$ lint_test
; Clean schema — no lint issues expected

% base
id n++
...
created_at d
updated_at d

# base users
name s
email s

# base orders
user_id n
total p
