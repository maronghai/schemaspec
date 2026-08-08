CREATE TABLE orders (
  id INT NOT NULL IDENTITY(1,1),
  user_id INT NOT NULL,
  total NUMERIC(12,2) NOT NULL,
  status NVARCHAR(50) NOT NULL,
  created_at DATETIME2 NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
