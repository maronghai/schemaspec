$ fix_test
; Schema with no timestamps — lint --fix should add created_at/updated_at

; Events table
# events
id n++
name s
data S
