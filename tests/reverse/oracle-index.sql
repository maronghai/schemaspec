CREATE TABLE orders (
  id NUMBER(10) NOT NULL,
  user_id NUMBER(10) NOT NULL,
  amount NUMBER(10, 2),
  status VARCHAR2(20) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);

CREATE INDEX idx_orders_user_id ON orders (user_id);
