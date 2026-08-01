CREATE TABLE orders (
  id INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
  user_id INTEGER NOT NULL,
  amount DECIMAL(10, 2),
  status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);

CREATE INDEX idx_orders_user_id ON orders (user_id);
